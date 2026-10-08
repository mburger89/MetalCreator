import CreatorGeometry

extension TermBuilder {
    func validateEntities() throws(SolveFailure) {
        for id in sketch.entityIDs {
            guard let entity = sketch.entities[id] else { continue }
            try validate(entity.kind, of: id)
        }
    }

    /// Refuses an entity no solve can use: a non-finite point, a curve not built on distinct
    /// points, or a circle without a positive radius.
    func validate(_ kind: SketchEntityKind, of id: SketchEntityID) throws(SolveFailure) {
        switch kind {
        case .point(let position):
            if !position.isFinite { throw SolveFailure(reason: "\(sketch.label(of: id)) has an invalid position.") }
        case .line(let start, let end):
            try requirePoints([start, end], of: id)
            if start == end { throw SolveFailure(reason: "\(sketch.label(of: id)) starts and ends at the same point.") }
        case .arc(let center, let start, let end):
            try requirePoints([center, start, end], of: id)
            if Set([center, start, end]).count < 3 {
                throw SolveFailure(reason: "\(sketch.label(of: id)) needs three different points.")
            }
        case .circle(let center, let radius):
            try requirePoints([center], of: id)
            if !(radius > 0) || !radius.isFinite {
                throw SolveFailure(reason: "\(sketch.label(of: id)) needs a radius greater than 0 mm.")
            }
        case .projected:
            break
        }
    }

    func requirePoints(_ ids: [SketchEntityID], of owner: SketchEntityID) throws(SolveFailure) {
        for id in ids {
            guard let kind = sketch.entities[id]?.kind, kind.isPoint else {
                throw SolveFailure(reason: "\(sketch.label(of: owner)) is built on something that isn't a point.")
            }
        }
    }

    func validate(_ dimension: SketchDimension) throws(SolveFailure) {
        let value = dimension.value
        let title = sketch.title(of: dimension)
        guard value.isFinite else { throw SolveFailure(reason: "\(title) is not a number.") }
        if case .angle = dimension.kind {
            guard value >= 0, value <= 180 else {
                throw SolveFailure(reason: "\(title) must be between 0° and 180°, not \(value.sketchDisplay)°.")
            }
        } else if !(value > 0) {
            throw SolveFailure(reason: "\(title) must be greater than 0 mm, not \(value.sketchDisplay) mm.")
        }
    }

    /// Refuses a constraint or dimension that names an entity the sketch no longer has (an
    /// edited or damaged file), instead of solving around it.
    func requireExisting(_ ids: [SketchEntityID], _ ref: SketchConstraintRef) throws(SolveFailure) {
        guard ids.allSatisfy({ sketch.entities[$0] != nil }) else {
            throw SolveFailure(reason: "\(sketch.label(of: ref)) refers to geometry that no longer exists.")
        }
    }

    func touchesSuspended(_ ids: [SketchEntityID]) -> Bool {
        ids.contains { id in
            if case .projected(let source) = sketch.entities[id]?.kind { return source.isSuspended }
            return false
        }
    }
}

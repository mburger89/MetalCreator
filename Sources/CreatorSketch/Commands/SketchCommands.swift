import CreatorGeometry

/// Pure sketch editing commands (spec §3): each takes a sketch and arguments and returns a
/// `SketchEdit`, never touching its input. Geometry is read at the current positions (the last
/// solve, else drawn), and new points get drawn and warm-start positions where they are created,
/// so the result solves without moving anything that was already in place.
public enum SketchCommands {}

extension SketchCommands {
    /// A curve's current shape, refusing points and projected edges.
    static func editableShape(_ sketch: Sketch, _ id: SketchEntityID, verb: String) throws(SketchCommandError) -> CurveShape {
        guard let entity = sketch.entities[id] else { throw SketchCommandError("That curve no longer exists.") }
        if case .projected = entity.kind { throw SketchCommandError("Projected edges can't be \(verb).") }
        guard !entity.kind.isPoint, let shape = sketch.shape(of: id) else {
            throw SketchCommandError("Pick a line, arc or circle.")
        }
        return shape
    }

    /// The point entity to end a curve at `position` on `cutter`: the cutter's own endpoint when
    /// one is there (shared, as lines and arcs share endpoints), else a new point held on the
    /// cutter by a point-on constraint.
    static func point(at position: Vector2, on cutter: SketchEntityID, in sketch: inout Sketch) -> SketchEntityID {
        if let shared = sharedEndpoint(of: cutter, at: position, in: sketch) { return shared }
        let point = newPoint(at: position, in: &sketch)
        sketch.add(.pointOn(point: point, curve: cutter))
        return point
    }

    /// The cutter's start or end point when it lies at `position`.
    static func sharedEndpoint(of cutter: SketchEntityID, at position: Vector2, in sketch: Sketch) -> SketchEntityID? {
        let ends: [SketchEntityID] = switch sketch.entities[cutter]?.kind {
        case .line(let start, let end), .arc(_, let start, let end): [start, end]
        default: []
        }
        return ends.first { sketch.position(of: $0).map { ($0 - position).length <= CurveIntersection.tolerance } ?? false }
    }

    /// A new point with matching drawn and warm-start positions.
    static func newPoint(at position: Vector2, in sketch: inout Sketch) -> SketchEntityID {
        let point = sketch.addPoint(position)
        sketch.solved[point] = .point(position)
        return point
    }

    /// Removes the constraints and dimensions on `curve` that depend on its extent and would
    /// fight a trim, extend or fillet: lengths, equal lengths and midpoints. Everything else on a
    /// curve treats lines as infinite and arcs as full circles, so it stays valid.
    static func removeExtentDependent(on curve: SketchEntityID, in sketch: inout Sketch) {
        let isLine = if case .line = sketch.entities[curve]?.kind { true } else { false }
        sketch.constraints = sketch.constraints.filter { _, constraint in
            switch constraint {
            case .equal(let a, let b): !(isLine && (a == curve || b == curve))
            case .midpoint(_, let line): line != curve
            default: true
            }
        }
        sketch.dimensions = sketch.dimensions.filter { _, dimension in
            if case .length(let line) = dimension.kind { return line != curve }
            return true
        }
    }

    /// Removes tangent constraints on `curve` that relied on it sharing `point` with the other curve.
    static func removeTangents(on curve: SketchEntityID, sharing point: SketchEntityID, in sketch: inout Sketch) {
        sketch.constraints = sketch.constraints.filter { _, constraint in
            guard case .tangent(let a, let b) = constraint, a == curve || b == curve else { return true }
            let other = a == curve ? b : a
            return !(sketch.entities[other]?.kind.referencedPoints.contains(point) ?? false)
        }
    }

    /// Moves tangent constraints between `curve` and curves sharing `point` onto `replacement`.
    static func moveTangents(on curve: SketchEntityID, sharing point: SketchEntityID, to replacement: SketchEntityID,
                             in sketch: inout Sketch) {
        for id in sketch.constraintIDs {
            guard case .tangent(let a, let b) = sketch.constraints[id], a == curve || b == curve else { continue }
            let other = a == curve ? b : a
            if sketch.entities[other]?.kind.referencedPoints.contains(point) ?? false {
                sketch.constraints[id] = .tangent(replacement, other)
            }
        }
    }

    /// The other non-point entities that use `point`.
    static func users(of point: SketchEntityID, besides curve: SketchEntityID? = nil, in sketch: Sketch) -> [SketchEntityID] {
        sketch.entityIDs.filter { $0 != curve && (sketch.entities[$0]?.kind.referencedPoints.contains(point) ?? false) }
    }
}

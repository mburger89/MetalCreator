import CreatorGeometry

extension SketchCommands {
    /// What one copy of a selection made: old point → new point (a point that stays put maps to
    /// itself) and each copied curve as (original, copy), in ID order.
    struct Copy {
        var points: [SketchEntityID: SketchEntityID] = [:]
        var curves: [(original: SketchEntityID, copy: SketchEntityID)] = []
    }

    /// The selection in ID order, refusing missing entities and projected edges.
    static func selection(_ ids: [SketchEntityID], in sketch: Sketch, verb: String) throws(SketchCommandError) -> [SketchEntityID] {
        let selected = Set(ids).sorted()
        guard !selected.isEmpty else { throw SketchCommandError("Select the geometry to \(verb) first.") }
        for id in selected {
            guard let entity = sketch.entities[id] else { throw SketchCommandError("Some of the selected geometry no longer exists.") }
            if case .projected = entity.kind { throw SketchCommandError("Projected edges can't be copied by \(verb).") }
        }
        return selected
    }

    /// Every point the selection uses (selected points and the curves' points), in ID order.
    static func points(of selection: [SketchEntityID], in sketch: Sketch) -> [SketchEntityID] {
        var points = Set<SketchEntityID>()
        for id in selection {
            guard let kind = sketch.entities[id]?.kind else { continue }
            if kind.isPoint { points.insert(id) } else { points.formUnion(kind.referencedPoints) }
        }
        return points.sorted()
    }

    /// Copies the selection, moving every point through `transform` except those `stays` keeps.
    /// `reversesArcs` swaps arc ends so a mirrored arc still runs counter-clockwise.
    static func copy(_ selection: [SketchEntityID], in sketch: inout Sketch, reversesArcs: Bool,
                     stays: (Vector2) -> Bool, transform: (Vector2) -> Vector2) -> Copy {
        var copy = Copy()
        for point in points(of: selection, in: sketch) {
            guard let position = sketch.position(of: point) else { continue }
            copy.points[point] = stays(position) ? point : newPoint(at: transform(position), in: &sketch)
        }
        for id in selection {
            guard let entity = sketch.entities[id], !entity.kind.isPoint else { continue }
            func mapped(_ point: SketchEntityID) -> SketchEntityID { copy.points[point] ?? point }
            let kind: SketchEntityKind = switch entity.kind {
            case .line(let start, let end): .line(start: mapped(start), end: mapped(end))
            case .arc(let center, let start, let end):
                reversesArcs ? .arc(center: mapped(center), start: mapped(end), end: mapped(start))
                    : .arc(center: mapped(center), start: mapped(start), end: mapped(end))
            case .circle(let center, _): .circle(center: mapped(center), radius: sketch.radius(of: id) ?? 1)
            case .point, .projected: entity.kind
            }
            let duplicate = sketch.add(SketchEntity(kind, isConstruction: entity.isConstruction))
            if case .circle = kind, let radius = sketch.radius(of: id) { sketch.solved[duplicate] = .radius(radius) }
            copy.curves.append((id, duplicate))
        }
        return copy
    }

    /// "1 entity", "3 entities".
    static func count(_ n: Int) -> String { n == 1 ? "1 entity" : "\(n) entities" }
}

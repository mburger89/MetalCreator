import CreatorGeometry

/// Assigns global unknown columns in entity-ID order: two per point (x, y), one per circle (radius).
/// Projected geometry has no unknowns.
struct UnknownLayout: Sendable {
    private(set) var pointColumns: [SketchEntityID: Int] = [:]
    private(set) var radiusColumns: [SketchEntityID: Int] = [:]
    /// For each column, the entity that owns it.
    private(set) var owners: [SketchEntityID] = []

    init(_ sketch: Sketch) {
        for id in sketch.entityIDs {
            switch sketch.entities[id]?.kind {
            case .point:
                pointColumns[id] = owners.count
                owners += [id, id]
            case .circle:
                radiusColumns[id] = owners.count
                owners.append(id)
            default:
                break
            }
        }
    }

    var columnCount: Int { owners.count }

    /// The warm start: each unknown's `solved` value, falling back to the drawn value (spec §4).
    func warmStart(_ sketch: Sketch) -> [Double] {
        var x = Array(repeating: 0.0, count: columnCount)
        for (id, column) in pointColumns {
            let position = sketch.position(of: id) ?? .zero
            x[column] = position.x
            x[column + 1] = position.y
        }
        for (id, column) in radiusColumns {
            x[column] = sketch.radius(of: id) ?? 0
        }
        return x
    }
}

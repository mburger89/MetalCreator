import CreatorGeometry

/// One active spline handle: the spline, the fit point's index and which of its two handles.
struct HandleKey: Hashable, Sendable, Comparable {
    var entity: SketchEntityID
    var index: Int
    var kind: SplineHandleKind

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.entity, lhs.index, lhs.kind) < (rhs.entity, rhs.index, rhs.kind)
    }
}

/// Assigns global unknown columns in entity-ID order: two per point (x, y), one per circle (radius), and two per active
/// spline handle (x, y), each spline's handles in fit-point order, tangent before curvature. A handle that is automatic has
/// no columns (the spline fills it in), so a spline of automatic handles is defined by its fit points alone.
/// Projected geometry has no unknowns.
struct UnknownLayout: Sendable {
    private(set) var pointColumns: [SketchEntityID: Int] = [:]
    private(set) var radiusColumns: [SketchEntityID: Int] = [:]
    private(set) var handleColumns: [HandleKey: Int] = [:]
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
            case .spline(let points, let states):
                for (index, state) in states.enumerated() where index < points.count {
                    for (kind, isActive) in [(SplineHandleKind.tangent, state.tangent), (.curvature, state.curvature)] where isActive {
                        handleColumns[HandleKey(entity: id, index: index, kind: kind)] = owners.count
                        owners += [id, id]
                    }
                }
            default:
                break
            }
        }
    }

    var columnCount: Int { owners.count }

    /// The first column of an active handle, or `nil` when it is automatic.
    func handleColumn(_ entity: SketchEntityID, _ index: Int, _ kind: SplineHandleKind) -> Int? {
        handleColumns[HandleKey(entity: entity, index: index, kind: kind)]
    }

    /// The warm start: each unknown's `solved` value, falling back to the drawn value (spec §4). An active handle with no
    /// stored value starts at what the automatic solve gives.
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
        for key in handleColumns.keys.sorted() {
            guard let column = handleColumns[key], let value = sketch.splineHandleValue(key.entity, key.index, key.kind) else { continue }
            x[column] = value.x
            x[column + 1] = value.y
        }
        return x
    }
}

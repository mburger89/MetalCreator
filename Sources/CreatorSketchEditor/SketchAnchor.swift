import CreatorGeometry
import CreatorSketch

/// Where a tool's click lands: on an existing point (shared, so the new curve is coincident with it structurally,
/// spec §3), or at a new position.
enum SketchAnchor: Hashable, Sendable {
    case existing(SketchEntityID, at: Vector2)
    case free(Vector2)

    var position: Vector2 {
        switch self {
        case .existing(_, let at), .free(let at): at
        }
    }

    var point: SketchEntityID? {
        if case .existing(let id, _) = self { return id }
        return nil
    }

    /// The anchor's point in `sketch`: the existing one, or a new one at its position.
    func point(in sketch: inout Sketch, isConstruction: Bool = false) -> SketchEntityID {
        switch self {
        case .existing(let id, _): id
        case .free(let at): sketch.addPoint(at, isConstruction: isConstruction)
        }
    }
}

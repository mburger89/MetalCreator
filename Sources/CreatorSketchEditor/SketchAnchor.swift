import CreatorGeometry
import CreatorSketch

/// Where a tool's click lands: on an existing point (shared, so the new curve is coincident with it structurally,
/// spec §3), on a curve (a new point held on it by point-on, sketcher spec §8's inference), or at a new position.
enum SketchAnchor: Hashable, Sendable {
    case existing(SketchEntityID, at: Vector2)
    case onCurve(SketchEntityID, at: Vector2)
    case free(Vector2)

    var position: Vector2 {
        switch self {
        case .existing(_, let at), .onCurve(_, let at), .free(let at): at
        }
    }

    var point: SketchEntityID? {
        if case .existing(let id, _) = self { return id }
        return nil
    }

    /// The curve a new point is held on, for `.onCurve`.
    var curve: SketchEntityID? {
        if case .onCurve(let id, _) = self { return id }
        return nil
    }

    /// The anchor's point in `sketch`: the existing one, or a new one at its position (held on its curve by point-on
    /// for `.onCurve`).
    func point(in sketch: inout Sketch, isConstruction: Bool = false) -> SketchEntityID {
        switch self {
        case .existing(let id, _):
            return id
        case .onCurve(let curve, let at):
            let point = sketch.addPoint(at, isConstruction: isConstruction)
            sketch.add(.pointOn(point: point, curve: curve))
            return point
        case .free(let at):
            return sketch.addPoint(at, isConstruction: isConstruction)
        }
    }
}

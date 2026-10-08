import CreatorGeometry
import Foundation

/// Measures dimensions on solved geometry, for reference (non-driving) dimensions (spec §3).
///
/// An angle reads in its dimension's stored `AngleSense`, the same sense a driving angle is
/// solved in, so a driving angle switched to reference reads back the value the user typed
/// however the lines run. Geometry swung past 0° the other way reads as the positive angle.
/// A dimension with no sense yet reads whichever of α and 180° − α is nearer its stored value.
enum SketchMeasure {
    static func referenceValues(_ sketch: Sketch, points: [SketchEntityID: Vector2],
                                radii: [SketchEntityID: Double]) -> [DimensionID: Double] {
        var values: [DimensionID: Double] = [:]
        for (id, dimension) in sketch.dimensions where !dimension.isDriving {
            values[id] = measure(dimension.kind, sketch, points: points, radii: radii, near: dimension.value,
                                 sense: dimension.angleSense)
        }
        return values
    }

    static func measure(_ kind: DimensionKind, _ sketch: Sketch, points: [SketchEntityID: Vector2],
                        radii: [SketchEntityID: Double], near stored: Double, sense: AngleSense? = nil) -> Double? {
        func line(_ id: SketchEntityID) -> (Vector2, Vector2)? {
            switch sketch.entities[id]?.kind {
            case .line(let start, let end):
                guard let a = points[start], let b = points[end] else { return nil }
                return (a, b)
            case .projected(let source):
                if case .line(let a, let b) = source.curve { return (a, b) }
                return nil
            default:
                return nil
            }
        }
        func radius(_ id: SketchEntityID) -> Double? {
            switch sketch.entities[id]?.kind {
            case .arc(let center, let start, _):
                guard let c = points[center], let s = points[start] else { return nil }
                return (s - c).length
            case .circle: return radii[id]
            case .projected(let source):
                switch source.curve {
                case .arc(_, let r, _, _), .circle(_, let r): return r
                case .line: return nil
                }
            default: return nil
            }
        }
        switch kind {
        case .distance(let a, let b):
            if let p = points[a], let q = points[b] { return (p - q).length }
            let (pointID, lineID) = points[a] != nil ? (a, b) : (b, a)
            guard let p = points[pointID], let (s, e) = line(lineID), let unit = SketchMath.normalized(e - s) else { return nil }
            return abs(SketchMath.cross(unit, p - s))
        case .length(let id):
            return line(id).map { ($0.1 - $0.0).length }
        case .radius(let id):
            return radius(id)
        case .diameter(let id):
            return radius(id).map { $0 * 2 }
        case .angle(let a, let b):
            guard let (s1, e1) = line(a), let (s2, e2) = line(b) else { return nil }
            let (d1, d2) = (e1 - s1, e2 - s2)
            if let sense { return abs(sense.degrees(from: d1, to: d2)) }
            let directed = abs(atan2(SketchMath.cross(d1, d2), SketchMath.dot(d1, d2))) * 180 / .pi
            let supplement = 180 - directed
            return abs(supplement - stored) < abs(directed - stored) ? supplement : directed
        }
    }
}

import CreatorGeometry
import CreatorSketch
import Foundation

/// One draggable knob of a spline's handles: the tangent handle has two (one each side of its fit point, `sign` +1 along the
/// tangent and -1 against it), the curvature handle one.
struct HandleKnob: Hashable, Sendable {
    var spline: SketchEntityID
    var index: Int
    var kind: SplineHandleKind
    var sign: Double
}

/// Where a spline's handles are drawn and how a dragged knob turns back into the handle's vector. A handle's vector is a
/// derivative with respect to the chord-length parameter, so its length is about 1 for a curve running at the chord's pace; a
/// knob is drawn `scale` (a third of the neighbouring chords) per unit of it. Pure.
enum SplineHandleGeometry {
    /// Where the curvature knob sits with no curvature, as a fraction of `scale`, so it can be seen and grabbed there.
    static let restingOffset = 0.6

    /// A third of the mean chord next to fit point `index`; at least 1e-6.
    static func scale(points: [Vector2], at index: Int) -> Double {
        var chords: [Double] = []
        if index > 0 { chords.append((points[index] - points[index - 1]).length) }
        if index < points.count - 1 { chords.append((points[index + 1] - points[index]).length) }
        let mean = chords.isEmpty ? 0 : chords.reduce(0, +) / Double(chords.count)
        return max(mean / 3, 1e-6)
    }

    static func tangentKnob(point: Vector2, tangent: Vector2, scale: Double, sign: Double) -> Vector2 {
        point + tangent * (scale * sign)
    }

    /// The tangent vector a knob at `knob` stands for.
    static func tangentValue(point: Vector2, knob: Vector2, scale: Double, sign: Double) -> Vector2 {
        (knob - point) * (sign / scale)
    }

    /// The left normal of a vector's direction (zero for a zero vector).
    static func leftNormal(of vector: Vector2) -> Vector2 {
        let length = vector.length
        guard length > 1e-12 else { return .zero }
        return Vector2(-vector.y / length, vector.x / length)
    }

    static func curvatureKnob(point: Vector2, tangent: Vector2, second: Vector2, scale: Double) -> Vector2 {
        let normal = leftNormal(of: tangent)
        let across = second.x * normal.x + second.y * normal.y
        return point + normal * (scale * restingOffset + across * scale * scale)
    }

    /// The second derivative a knob at `knob` stands for: the current one's component along the tangent is kept, the normal
    /// one follows the knob. `nil` while the tangent has no direction.
    static func curvatureValue(point: Vector2, knob: Vector2, tangent: Vector2, second: Vector2, scale: Double) -> Vector2? {
        let normal = leftNormal(of: tangent)
        guard normal != .zero else { return nil }
        let direction = Vector2(normal.y, -normal.x)
        let along = second.x * direction.x + second.y * direction.y
        let offset = (knob - point).x * normal.x + (knob - point).y * normal.y
        return direction * along + normal * ((offset - scale * restingOffset) / (scale * scale))
    }

    /// The knobs of one fit point, with where each is drawn.
    static func knobs(of spline: SketchEntityID, at index: Int, definition: SplineDefinition) -> [(knob: HandleKnob, at: Vector2)] {
        guard definition.points.indices.contains(index) else { return [] }
        let point = definition.points[index]
        let resolved = definition.resolvedHandles()[index]
        let scale = scale(points: definition.points, at: index)
        var result: [(HandleKnob, Vector2)] = []
        for sign in [1.0, -1.0] {
            result.append((HandleKnob(spline: spline, index: index, kind: .tangent, sign: sign),
                           tangentKnob(point: point, tangent: resolved.tangent, scale: scale, sign: sign)))
        }
        result.append((HandleKnob(spline: spline, index: index, kind: .curvature, sign: 1),
                       curvatureKnob(point: point, tangent: resolved.tangent, second: resolved.secondDerivative, scale: scale)))
        return result
    }

    /// The handle's glyph as a polyline: a line through the point for the tangent, a short arc round it for the curvature.
    static func glyph(of knob: HandleKnob, at position: Vector2, point: Vector2) -> [Vector2] {
        switch knob.kind {
        case .tangent:
            return [point, position]
        case .curvature:
            let offset = position - point
            let radius = offset.length
            guard radius > 1e-9 else { return [position] }
            let middle = atan2(offset.y, offset.x)
            return (-4...4).map { step in
                let angle = middle + Double(step) * 0.09
                return point + Vector2(cos(angle), sin(angle)) * radius
            }
        }
    }
}

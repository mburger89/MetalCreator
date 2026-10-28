import CreatorGeometry
import Foundation

extension DimensionLayout {
    /// How many straight pieces the arc is drawn with (even, so one vertex is the arc's middle).
    private static let arcSteps = 24

    /// An angle: an arc over the smaller angle between two rays with an arrow at each end, the text at its middle in a
    /// break of the arc, and extension lines along a ray whose point is short of the arc. `nil` for a missing ray, rays
    /// that coincide, a plane seen too nearly edge-on, or anything not projectable.
    @MainActor
    static func placeAngular(_ dimension: OverlayDimension, style: DimensionStyle, camera: DimensionCamera,
                             measure: TextMeasure) -> PlacedDimension? {
        guard case let .angular(vertex, first, second, normal, placement) = dimension.geometry,
              vertex.isFinite, first.isFinite, second.isFinite, let n = normal.normalized,
              let u1 = (first - vertex).inPlane(n), let u2 = (second - vertex).inPlane(n),
              let view = camera.viewDirection(at: vertex), abs(n.dot(view)) >= sin(style.edgeOnLimit) else { return nil }
        let crossed = u1.cross(u2)
        let angle = atan2(crossed.length, u1.dot(u2))
        guard angle > 1e-6 else { return nil }
        let turn = n.cross(u1) * (crossed.dot(n) < 0 ? -1 : 1)

        guard let radius = arcRadius(placement, vertex: vertex, along: u1, style: style, camera: camera) else { return nil }

        var arc: [ScreenPoint] = []
        for step in 0...arcSteps {
            let phi = angle * Double(step) / Double(arcSteps)
            guard let point = camera.project(vertex + (u1 * cos(phi) + turn * sin(phi)) * radius) else { return nil }
            arc.append(point)
        }
        guard let start = arc.first, let end = arc.last, let startNext = arc.dropFirst().first, let endPrevious = arc.dropLast().last,
              let startDirection = (start - startNext).unit, let endDirection = (end - endPrevious).unit else { return nil }

        let textSize = textBoxSize(for: dimension.text, measure: measure)
        let centre = arc[arcSteps / 2]
        let origin = ScreenPoint(centre.x - textSize.width / 2, centre.y - textSize.height / 2)
        let gap = Box(minX: origin.x - style.textGap, minY: origin.y - style.textGap,
                      maxX: origin.x + textSize.width + style.textGap, maxY: origin.y + textSize.height + style.textGap)

        var segments = zip(arc, arc.dropFirst()).flatMap { gap.outside(of: ScreenSegment($0, $1)) }
        for (ray, arcEnd) in [(first, start), (second, end)] where (ray - vertex).length < radius {
            guard let point = camera.project(ray), let line = extensionLine(from: point, to: arcEnd, style: style) else { continue }
            segments.append(line)
        }
        let placed = PlacedDimension(
            id: dimension.id, text: dimension.text, tint: dimension.tint, isGhosted: dimension.isGhosted, segments: segments,
            arrows: [.init(tip: start, direction: startDirection), .init(tip: end, direction: endDirection)],
            textOrigin: origin, textSize: textSize,
            pinMark: dimension.isPinned ? ScreenPoint(origin.x + textSize.width, origin.y) : nil)
        return placed.isFinite ? placed : nil
    }

    /// The arc's radius in millimetres: through a saved point, or a standoff in points from the vertex.
    private static func arcRadius(_ placement: DimensionPlacement, vertex: Vector3, along ray: Vector3, style: DimensionStyle,
                                  camera: DimensionCamera) -> Double? {
        let radius: Double
        switch placement {
        case let .through(point):
            guard point.isFinite else { return nil }
            radius = (point - vertex).length
        case .standoff:
            guard let scale = camera.pointsPerMillimetre(at: vertex, along: ray), scale > 1e-9 else { return nil }
            radius = (style.standoff + style.leaderLength) / scale
        }
        return radius.isFinite && radius > 1e-9 ? radius : nil
    }

    /// An axis-aligned rectangle on screen, used to cut the arc where the text sits.
    private struct Box {
        var minX: Double, minY: Double, maxX: Double, maxY: Double

        /// The parts of `segment` outside the box (none, one or two).
        func outside(of segment: ScreenSegment) -> [ScreenSegment] {
            let (dx, dy) = (segment.b.x - segment.a.x, segment.b.y - segment.a.y)
            var (enter, leave) = (0.0, 1.0)
            for (delta, low, high, origin) in [(dx, minX, maxX, segment.a.x), (dy, minY, maxY, segment.a.y)] {
                if abs(delta) < 1e-12 {
                    if origin <= low || origin >= high { return [segment] }
                } else {
                    let (t1, t2) = ((low - origin) / delta, (high - origin) / delta)
                    enter = max(enter, min(t1, t2))
                    leave = min(leave, max(t1, t2))
                }
            }
            guard enter < leave else { return [segment] }
            func point(_ t: Double) -> ScreenPoint { ScreenPoint(segment.a.x + dx * t, segment.a.y + dy * t) }
            var pieces: [ScreenSegment] = []
            if enter > 0 { pieces.append(ScreenSegment(segment.a, point(enter))) }
            if leave < 1 { pieces.append(ScreenSegment(point(leave), segment.b)) }
            return pieces
        }
    }
}

private extension Vector3 {
    /// This vector's part in the plane with unit normal `n`, normalised, or `nil` when it has none.
    func inPlane(_ n: Vector3) -> Vector3? {
        (self - n * dot(n)).normalized
    }
}

private extension ScreenPoint {
    /// This offset as a unit vector, or `nil` when it has no length.
    var unit: Vector2? {
        length < 1e-9 ? nil : Vector2(x / length, y / length)
    }
}

import CreatorGeometry
import Foundation

extension DimensionLayout {
    /// The text box size for `text`: the measured width (rounded up) and the fixed height, plus padding.
    @MainActor
    static func textBoxSize(for text: String, measure: TextMeasure) -> ViewportSize {
        ViewportSize(width: measure(text).width.rounded(.up) + 2 * PlacedDimension.textPadding, height: PlacedDimension.textHeight)
    }

    /// A radius or diameter: an arrow on the circle, a leader running outward, a horizontal shoulder and the text beyond it.
    /// `nil` for a radius that is not positive, no plane or aim, a circle seen too nearly edge-on, or anything not projectable.
    @MainActor
    static func placeRadial(_ dimension: OverlayDimension, style: DimensionStyle, camera: DimensionCamera,
                            measure: TextMeasure) -> PlacedDimension? {
        guard case let .radial(center, radius, normal, toward, placement) = dimension.geometry,
              center.isFinite, radius.isFinite, radius > 0, let n = normal.normalized, toward.isFinite,
              let aim = (toward - n * toward.dot(n)).normalized,
              let view = camera.viewDirection(at: center), abs(n.dot(view)) >= sin(style.edgeOnLimit),
              let centreScreen = camera.project(center), let tip = camera.project(center + aim * radius) else { return nil }
        let outward = tip - centreScreen
        guard outward.length >= 1e-6 else { return nil }
        let unit = Vector2(outward.x / outward.length, outward.y / outward.length)

        let leaderEnd: ScreenPoint
        switch placement {
        case let .through(point):
            guard let projected = camera.project(point) else { return nil }
            leaderEnd = projected
        case .standoff:
            leaderEnd = tip.moved(along: unit, by: style.leaderLength)
        }
        let leader = leaderEnd - tip
        guard leader.length >= 1e-6 else { return nil }
        let sign: Double = leaderEnd.x - centreScreen.x < 0 ? -1 : 1
        let shoulderEnd = ScreenPoint(leaderEnd.x + sign * style.shoulderLength, leaderEnd.y)

        let textSize = textBoxSize(for: dimension.text, measure: measure)
        let origin = ScreenPoint(sign > 0 ? shoulderEnd.x + style.textGap : shoulderEnd.x - style.textGap - textSize.width,
                                 shoulderEnd.y - textSize.height / 2)
        let direction = Vector2(-leader.x / leader.length, -leader.y / leader.length)
        let placed = PlacedDimension(
            id: dimension.id, text: dimension.text, tint: dimension.tint, isGhosted: dimension.isGhosted,
            segments: [ScreenSegment(tip, leaderEnd), ScreenSegment(leaderEnd, shoulderEnd)],
            arrows: [.init(tip: tip, direction: direction)], textOrigin: origin, textSize: textSize,
            pinMark: dimension.isPinned ? ScreenPoint(origin.x + textSize.width, origin.y) : nil)
        return placed.isFinite ? placed : nil
    }
}

import CreatorGeometry
import Foundation

extension DimensionLayout {
    /// The dimension line's ends and the points it measures, on screen.
    private struct LinearEnds {
        var from: ScreenPoint, to: ScreenPoint, a: ScreenPoint, b: ScreenPoint
    }

    @MainActor
    static func placeLinear(_ dimension: OverlayDimension, style: DimensionStyle, camera: DimensionCamera,
                            measure: TextMeasure) -> PlacedDimension? {
        guard let ends = linearEnds(dimension.geometry, style: style, camera: camera) else { return nil }
        let (aScreen, bScreen) = (ends.a, ends.b)
        let span = bScreen - aScreen
        guard span.length >= 1 else { return nil }

        var segments = [(ends.from, aScreen), (ends.to, bScreen)].compactMap { extensionLine(from: $0, to: $1, style: style) }
        let textSize = ViewportSize(width: measure(dimension.text).width.rounded(.up) + 2 * PlacedDimension.textPadding,
                                    height: PlacedDimension.textHeight)
        let u = Vector2(span.x / span.length, span.y / span.length)
        let back = Vector2(-u.x, -u.y)
        let along = abs(u.x) * textSize.width + abs(u.y) * textSize.height
        let fits = span.length >= along + 2 * style.textGap + 2 * style.arrowLength

        let arrows: [PlacedDimension.Arrow]
        let centre: ScreenPoint
        if fits {
            arrows = [.init(tip: aScreen, direction: back), .init(tip: bScreen, direction: u)]
            centre = ScreenPoint((aScreen.x + bScreen.x) / 2, (aScreen.y + bScreen.y) / 2)
            let half = along / 2 + style.textGap
            segments.append(ScreenSegment(aScreen, centre.moved(along: back, by: half)))
            segments.append(ScreenSegment(centre.moved(along: u, by: half), bScreen))
        } else {
            let leader = 2 * style.arrowLength
            arrows = [.init(tip: aScreen, direction: u), .init(tip: bScreen, direction: back)]
            segments.append(ScreenSegment(aScreen, bScreen))
            segments.append(ScreenSegment(aScreen, aScreen.moved(along: back, by: leader)))
            segments.append(ScreenSegment(bScreen, bScreen.moved(along: u, by: leader)))
            centre = bScreen.moved(along: u, by: leader + style.textGap + along / 2)
        }

        let origin = ScreenPoint(centre.x - textSize.width / 2, centre.y - textSize.height / 2)
        let placed = PlacedDimension(
            id: dimension.id, text: dimension.text, tint: dimension.tint, isGhosted: dimension.isGhosted, segments: segments,
            arrows: arrows, textOrigin: origin, textSize: textSize,
            pinMark: dimension.isPinned ? ScreenPoint(origin.x + textSize.width, origin.y) : nil)
        return placed.isFinite ? placed : nil
    }

    /// The projected measured points and dimension-line ends of a linear dimension, or `nil` when it has no length,
    /// is seen too nearly edge-on, or a point cannot be projected.
    private static func linearEnds(_ geometry: DimensionGeometry, style: DimensionStyle, camera: DimensionCamera) -> LinearEnds? {
        guard case let .linear(from, to, direction, side, placement) = geometry,
              from.isFinite, to.isFinite, let d = direction.normalized, let s = side.normalized,
              let normal = d.cross(s).normalized else { return nil }
        let mid = (from + to) * 0.5
        guard let view = camera.viewDirection(at: mid), abs(normal.dot(view)) >= sin(style.edgeOnLimit) else { return nil }

        let (ea, eb) = (from.dot(s), to.dot(s))
        let offset: Double
        switch placement {
        case let .through(point):
            guard point.isFinite else { return nil }
            offset = point.dot(s)
        case .standoff:
            guard let scale = camera.pointsPerMillimetre(at: mid, along: s), scale > 1e-9 else { return nil }
            offset = max(ea, eb) + style.standoff / scale
        }
        guard let fromScreen = camera.project(from), let toScreen = camera.project(to),
              let a = camera.project(from + s * (offset - ea)), let b = camera.project(to + s * (offset - eb)) else { return nil }
        return LinearEnds(from: fromScreen, to: toScreen, a: a, b: b)
    }

    /// An extension line from `point` to the dimension line at `line`: it leaves a gap at the point and runs past the line.
    /// None when the point is within the gap of the line.
    private static func extensionLine(from point: ScreenPoint, to line: ScreenPoint, style: DimensionStyle) -> ScreenSegment? {
        let e = line - point
        guard e.length > style.extensionGap else { return nil }
        let unit = Vector2(e.x / e.length, e.y / e.length)
        return ScreenSegment(point.moved(along: unit, by: style.extensionGap), line.moved(along: unit, by: style.extensionOvershoot))
    }
}

private extension ScreenPoint {
    func moved(along direction: Vector2, by distance: Double) -> ScreenPoint {
        ScreenPoint(x + direction.x * distance, y + direction.y * distance)
    }
}

extension PlacedDimension {
    /// Whether every coordinate is a finite number: nothing NaN or infinite is ever handed to the view.
    var isFinite: Bool {
        let points = segments.flatMap { [$0.a, $0.b] } + arrows.map(\.tip) + [textOrigin] + (pinMark.map { [$0] } ?? [])
        return points.allSatisfy { $0.x.isFinite && $0.y.isFinite } && arrows.allSatisfy { $0.direction.isFinite }
            && textSize.width.isFinite && textSize.height.isFinite
    }
}

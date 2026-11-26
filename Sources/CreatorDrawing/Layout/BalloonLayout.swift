import CreatorGeometry
import Foundation

/// A balloon in sheet millimetres (DR-5 R4): the number centred in a thin circle and a leader from the circle toward the foot,
/// ending in a filled arrowhead on it. Everything is for the dimension layer; the composer tags it.
public enum BalloonLayout {
    public static func draw(number: String, center: Vector2, foot: Vector2?, h: Double, style: AnnotationStyle) -> AnnotationDrawing {
        let sizes = BalloonStyle.of(style.standard)
        let capHeight = sizes.text * h
        let run = DrawingText.layout(number, height: capHeight)
        let radius = Swift.max(sizes.radius * h, run.width / 2 + sizes.padding * h)
        var builder = DrawingBuilder(style: style, height: capHeight)
        builder.drawing.segments.append(.arc(center: center, radius: radius, start: 0, sweep: 2 * .pi))
        builder.drawing.texts.append(
            PlacedText(
                run: run, original: number, origin: Vector2(center.x - run.width / 2, center.y - capHeight / 2), height: capHeight,
                angle: 0))
        builder.drawing.textCenter = center
        if let foot {
            let along = foot - center
            let distance = along.length
            if distance > radius + 1e-9 {
                let unit = along * (1 / distance)
                builder.line(center + unit * radius, foot)
                builder.arrow(tip: foot, back: unit * -1)
            }
        }
        return builder.finish()
    }
}

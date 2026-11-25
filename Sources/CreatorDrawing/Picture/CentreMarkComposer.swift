import CreatorGeometry
import CreatorKernel

/// Centre marks and centre lines on the sheet (plan R13): thin chain lines on `.center`.
enum CentreMarkComposer {
    /// What a stroke is tagged with.
    struct Tag {
        var view: ViewID?
        var annotation: AnnotationID?
        var isLost: Bool
    }

    /// The two styles every mark takes its sizes and weights from.
    struct Styles {
        var annotation: AnnotationStyle
        var drawing: DrawingStyle
    }

    /// Circles whose centres lie within this many model millimetres share one mark.
    static let concentric = 1e-6

    /// The automatic marks of a projection: one per visible full circle of an edge, concentric circles sharing the largest.
    static func automatic(
        projection: Projection2D, view: ViewID, mapping: ViewMapping, styles: Styles
    ) -> [SheetStroke] {
        var circles: [(center: Vector2, radius: Double)] = []
        for line in projection.lines where line.visibility == .visible {
            guard case .arc(let center, let radius, _, let sweep) = line.curve, abs(sweep) >= 2 * .pi - 1e-9,
                case .edge? = line.source
            else { continue }
            if let index = circles.firstIndex(where: { ($0.center - center).length <= concentric }) {
                circles[index].radius = Swift.max(circles[index].radius, radius)
            } else {
                circles.append((center, radius))
            }
        }
        let tag = Tag(view: view, annotation: nil, isLost: false)
        return circles.flatMap { mark(center: $0.center, radius: $0.radius, mapping: mapping, tag: tag, styles: styles) }
    }

    /// The two lines through `center` (model plane), reaching `radius x scale + centreOvershoot` each way; solid on a small circle.
    static func mark(
        center: Vector2, radius: Double, mapping: ViewMapping, tag: Tag, styles: Styles
    ) -> [SheetStroke] {
        let at = mapping.sheet(center)
        let onSheet = radius * mapping.scale
        let reach = onSheet + styles.annotation.centreOvershoot
        let pattern: StrokePattern = onSheet < styles.annotation.smallCentre ? .solid : .centre
        return [Vector2(1, 0), Vector2(0, 1)].map { along in
            SheetStroke(
                segments: [.line(at - along * reach, at + along * reach)], width: styles.drawing.thin, pattern: pattern,
                layer: .center, view: tag.view, annotation: tag.annotation, isLost: tag.isLost)
        }
    }

    /// A chain line along an axis, `centreOvershoot` past each end.
    static func line(
        start: Vector2, end: Vector2, mapping: ViewMapping, tag: Tag, styles: Styles
    ) -> [SheetStroke] {
        let a = mapping.sheet(start), b = mapping.sheet(end)
        let length = (b - a).length
        guard length > 1e-12 else { return [] }
        let along = (b - a) * (1 / length)
        let over = styles.annotation.centreOvershoot
        return [
            SheetStroke(
                segments: [.line(a - along * over, b + along * over)], width: styles.drawing.thin, pattern: .centre,
                layer: .center, view: tag.view, annotation: tag.annotation, isLost: tag.isLost),
        ]
    }
}

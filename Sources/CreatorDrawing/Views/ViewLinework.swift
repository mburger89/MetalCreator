import CreatorGeometry
import CreatorKernel

/// A projection's lines as sheet strokes (plan R11).
public enum ViewLinework {
    public static func strokes(
        for projection: Projection2D, view: DrawingView, center: Vector2, scale: Double, style: DrawingStyle
    ) -> [SheetStroke] {
        guard let mapping = ViewMapping.of(projection: projection, center: center, scale: scale) else { return [] }
        return strokes(for: projection, mapping: mapping, view: view, style: style)
    }

    /// The strokes of a view's content, mapped by its framing (R10).
    public static func strokes(
        for content: ViewContent, view: DrawingView, center: Vector2, scale: Double, style: DrawingStyle
    ) -> [SheetStroke] {
        guard let projection = content.projection,
            let mapping = ViewMapping.of(content: content, center: center, scale: scale)
        else { return [] }
        return strokes(for: projection, mapping: mapping, view: view, style: style)
    }

    private static func strokes(
        for projection: Projection2D, mapping: ViewMapping, view: DrawingView, style: DrawingStyle
    ) -> [SheetStroke] {
        var result: [SheetStroke] = []
        for line in projection.lines {
            guard let look = look(of: line, view: view, style: style) else { continue }
            result.append(
                SheetStroke(
                    segments: [segment(of: line.curve).transformed(scale: mapping.scale, offset: mapping.offset)], width: look.width,
                    pattern: look.pattern, layer: look.layer, view: view.id, source: line.source))
        }
        return result
    }

    /// The box the projection fills on the sheet, `nil` with no lines.
    public static func frame(for projection: Projection2D, center: Vector2, scale: Double) -> Rect2D? {
        guard let bounds = projection.bounds else { return nil }
        let half = Vector2(bounds.width * scale / 2, bounds.height * scale / 2)
        return Rect2D(min: center - half, max: center + half)
    }

    /// The box a view's content fills on the sheet (its framing, else the projection's bounds), `nil` with neither.
    public static func frame(for content: ViewContent, center: Vector2, scale: Double) -> Rect2D? {
        guard let box = content.framing ?? content.projection?.bounds else { return nil }
        let half = Vector2(box.width * scale / 2, box.height * scale / 2)
        return Rect2D(min: center - half, max: center + half)
    }

    private static func look(
        of line: ProjectedLine, view: DrawingView, style: DrawingStyle
    ) -> (width: Double, pattern: StrokePattern, layer: DrawingLayer)? {
        switch (line.visibility, line.lineClass) {
        case (.visible, .smooth):
            return view.showsTangent ? (style.thin, .solid, .tangent) : nil
        case (.hidden, .smooth):
            return nil
        case (.visible, _):
            return (style.thick, .solid, .visible)
        case (.hidden, _):
            return view.showsHidden ? (style.thin, .hidden, .hidden) : nil
        }
    }

    private static func segment(of curve: ProjectedCurve) -> SheetSegment {
        switch curve {
        case let .line(a, b): .line(a, b)
        case let .arc(center, radius, start, sweep): .arc(center: center, radius: radius, start: start, sweep: sweep)
        case let .ellipse(center, axis, major, minor, start, sweep):
            .ellipse(center: center, majorAxis: axis, majorRadius: major, minorRadius: minor, start: start, sweep: sweep)
        case let .polyline(points): .polyline(points)
        }
    }
}

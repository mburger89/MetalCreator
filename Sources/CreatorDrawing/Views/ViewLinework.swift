import CreatorGeometry
import CreatorKernel

/// A projection's lines as sheet strokes (plan R11).
public enum ViewLinework {
    public static func strokes(
        for projection: Projection2D, view: DrawingView, center: Vector2, scale: Double, style: DrawingStyle
    ) -> [SheetStroke] {
        guard let mapping = ViewMapping.of(projection: projection, center: center, scale: scale) else { return [] }
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

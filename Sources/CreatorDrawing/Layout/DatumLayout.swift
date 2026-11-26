import CreatorGeometry

// swiftlint:disable function_parameter_count
// The entry points take one argument per decision of the plan's R5, so they exceed the parameter limit.

/// The datum feature symbol in sheet millimetres (plan R5): a filled triangle, a leader and a square holding the letter.
public enum DatumLayout {
    /// On a line of the view: the triangle's base on the line, centred on `foot`, the square `distance` away on the side of its sign.
    /// With `edgeEnds` (the edge's end points on the sheet) a foot beyond them gets an extension line.
    public static func onLine(
        letter: String, foot: Vector2, along: Vector2, distance: Double, edgeEnds: (Vector2, Vector2)?, h: Double,
        style: AnnotationStyle
    ) -> AnnotationDrawing {
        let length = along.length
        guard length > 1e-12 else { return AnnotationDrawing() }
        let along = along * (1 / length)
        let normal = Vector2(-along.y, along.x)
        let side = distance < 0 ? -1.0 : 1.0
        var builder = DrawingBuilder(style: style, height: h)
        if let ends = edgeEnds { extensionLine(&builder, foot: foot, along: along, ends: ends, h: h) }
        symbol(&builder, letter: letter, foot: foot, along: along, toward: normal * side, distance: Swift.abs(distance), h: h)
        return builder.finish()
    }

    /// On the end of a dimension line: the triangle's base square to the line at `end`, its apex pointing away from `other`.
    public static func onDimensionLine(
        letter: String, end: Vector2, other: Vector2, distance: Double, h: Double, style: AnnotationStyle
    ) -> AnnotationDrawing {
        let direction = end - other
        let length = direction.length
        let outward = length > 1e-12 ? direction * (1 / length) : Vector2(1, 0)
        var builder = DrawingBuilder(style: style, height: h)
        symbol(
            &builder, letter: letter, foot: end, along: Vector2(-outward.y, outward.x), toward: outward, distance: Swift.abs(distance),
            h: h)
        return builder.finish()
    }

    /// Hanging below the middle of a label's bottom edge: the triangle's base horizontal, its apex down.
    public static func hanging(
        letter: String, below bottomMiddle: Vector2, distance: Double, h: Double, style: AnnotationStyle
    ) -> AnnotationDrawing {
        var builder = DrawingBuilder(style: style, height: h)
        symbol(
            &builder, letter: letter, foot: bottomMiddle, along: Vector2(1, 0), toward: Vector2(0, -1), distance: Swift.abs(distance),
            h: h)
        return builder.finish()
    }

    /// The least distance from the foot to the square's centre: the triangle's height, the leader's least length and half the
    /// square twice over (plan R5).
    public static func minimumDistance(h: Double) -> Double {
        let style = SymbolStyle.of(.iso)
        return style.datumTriangle * h * DrawingSymbols.sixty + style.datumLeaderMinimum * h + style.datumSquare * h / 2
    }

    private static func symbol(
        _ builder: inout DrawingBuilder, letter: String, foot: Vector2, along: Vector2, toward: Vector2, distance: Double, h: Double
    ) {
        let style = SymbolStyle.of(.iso)
        let reach = Swift.max(distance, minimumDistance(h: h))
        let triangle = DrawingSymbols.datumTriangle(foot: foot, along: along, toward: toward, h: h)
        builder.drawing.fills.append(triangle)
        let centre = foot + toward * reach
        builder.drawing.segments.append(.polyline(DrawingSymbols.datumSquare(center: centre, h: h)))
        let run = DrawingText.layout(letter, height: h)
        builder.drawing.texts.append(
            PlacedText(run: run, original: letter, origin: Vector2(centre.x - run.width / 2, centre.y - h / 2), height: h, angle: 0))
        // The leader runs from the apex toward the square's centre and stops on its edge.
        let apex = triangle[2]
        let way = centre - apex
        let length = way.length
        guard length > 1e-12 else { return }
        let unit = way * (1 / length)
        let half = style.datumSquare * h / 2
        let stop = centre - unit * (half / Swift.max(Swift.abs(unit.x), Swift.abs(unit.y)))
        if (stop - apex).length > 1e-12, DrawingBuilder.dot(stop - apex, unit) > 0 { builder.line(apex, stop) }
    }

    /// A thin line from the edge's nearer end, `extensionGap` clear of it, past the triangle by `extensionOvershoot`.
    private static func extensionLine(
        _ builder: inout DrawingBuilder, foot: Vector2, along: Vector2, ends: (Vector2, Vector2), h: Double
    ) {
        let length = along.length
        guard length > 1e-12 else { return }
        let unit = along * (1 / length)
        let first = DrawingBuilder.dot(ends.0 - foot, unit), second = DrawingBuilder.dot(ends.1 - foot, unit)
        let tolerance = 1e-9
        // Positions of the ends along the line, measured from the foot: the foot is beyond both when they share a sign.
        let nearest: Vector2
        if first < -tolerance, second < -tolerance {
            nearest = first > second ? ends.0 : ends.1
        } else if first > tolerance, second > tolerance {
            nearest = first < second ? ends.0 : ends.1
        } else {
            return
        }
        let toFoot = foot - nearest
        let distance = toFoot.length
        guard distance > 1e-12 else { return }
        let direction = toFoot * (1 / distance)
        let half = SymbolStyle.of(.iso).datumTriangle * h / 2
        builder.line(nearest + direction * builder.style.extensionGap, foot + direction * (half + builder.style.extensionOvershoot))
    }
}

// swiftlint:enable function_parameter_count

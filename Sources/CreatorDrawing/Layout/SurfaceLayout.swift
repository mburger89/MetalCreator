import CreatorGeometry

/// The surface texture symbol in sheet millimetres (plan R6).
public enum SurfaceLayout {
    /// The symbol with its lay, standing on a horizontal line at `foot` (no offset) or on a leader from an arrowhead at `foot`.
    public static func draw(
        _ texture: SurfaceTexture, foot: Vector2, along: Vector2, h: Double, format: NumberFormat, style: AnnotationStyle
    ) -> AnnotationDrawing {
        let symbolStyle = SymbolStyle.of(style.standard)
        var builder = DrawingBuilder(style: style, height: h)
        let stands = texture.offset == nil && Swift.abs(along.y) <= 1e-9
        var apex = foot
        if !stands {
            let offset = texture.offset ?? symbolStyle.defaultSurfaceOffset * h
            apex = foot + offset
            let way = apex - foot
            let length = way.length
            if length > 1e-12 {
                builder.arrow(tip: foot, back: way * (1 / length))
                builder.line(foot, apex)
            }
        }
        var drawing = requirement(texture.requirement, apex: apex, h: h, format: format)
        if let lay = texture.lay {
            let origin = apex + symbolStyle.layOrigin * h
            if lay == .perpendicular {
                drawing.segments += DrawingSymbols.layPerpendicular(origin: origin, h: h)
            } else {
                let text = layText(lay)
                let run = DrawingText.layout(text, height: h)
                drawing.texts.append(PlacedText(run: run, original: text, origin: origin, height: h, angle: 0))
            }
        }
        builder.drawing.segments += drawing.segments
        builder.drawing.texts += drawing.texts
        return builder.finish()
    }

    /// The standing symbol alone, from its apex: the legs, the process mark, and the parameter and value under a line.
    public static func requirement(
        _ requirement: SurfaceRequirement, apex: Vector2, h: Double, format: NumberFormat
    ) -> AnnotationDrawing {
        let style = SymbolStyle.of(.iso)
        var drawing = AnnotationDrawing()
        var parts: [String] = []
        if let parameter = requirement.parameter { parts.append(parameter.title) }
        if let value = requirement.value { parts.append(GDTNumber.roughness(value, format: format)) }
        let text = parts.joined(separator: " ")
        if text.isEmpty {
            drawing.segments = DrawingSymbols.surface(requirement.process, apex: apex, h: h, extension: nil)
        } else {
            let run = DrawingText.layout(text, height: h)
            let gap = style.surfaceTextGap * h
            drawing.segments = DrawingSymbols.surface(requirement.process, apex: apex, h: h, extension: gap + run.width + gap)
            let origin = Vector2(
                apex.x + style.surfaceLong * h * DrawingSymbols.slant + gap, apex.y + style.surfaceLong * h - h - gap)
            drawing.texts.append(PlacedText(run: run, original: text, origin: origin, height: h, angle: 0))
        }
        drawing.fitFrame()
        return drawing
    }

    /// The lay's letter; the perpendicular lay is a glyph, and `plainText` names it.
    static func layText(_ lay: SurfaceLay) -> String {
        switch lay {
        case .parallel: "="
        case .perpendicular: "⊥"
        case .crossed: "X"
        case .multidirectional: "M"
        case .circular: "C"
        case .radial: "R"
        case .particulate: "P"
        }
    }
}

extension DatumFeature {
    /// A text for lists and warnings, never drawn.
    public var plainText: String { "Datum " + letter }
}

extension SurfaceTexture {
    /// A text for lists and warnings, never drawn: "Surface texture Ra 1.6 lay X".
    public var plainText: String {
        let format = NumberFormat(units: .millimetres, standard: .iso, decimalSign: .point)
        var text = "Surface texture"
        if let parameter = requirement.parameter { text += " " + parameter.title }
        if let value = requirement.value { text += " " + GDTNumber.roughness(value, format: format) }
        if let lay { text += " lay " + SurfaceLayout.layText(lay) }
        return text
    }
}

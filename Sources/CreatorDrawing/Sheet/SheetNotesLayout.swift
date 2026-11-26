import CreatorGeometry

/// A sheet's general notes above the title block (plan R12): the general surface requirement standing right-aligned to the block
/// with "(", the basic symbol and ")" after it when the sheet has surface symbols, and above it the numbered notes, the edge break
/// last. Sheet millimetres; everything on the text layer.
public enum SheetNotesLayout {
    /// `base` is the y the notes stand on instead of the title block's top, when a parts list stands on the block (DR-5 R7).
    public static func picture(
        for sheet: DrawingSheet, settings: DrawingSettings, format: NumberFormat, base: Double? = nil
    ) -> SheetPicture {
        var picture = SheetPicture(size: sheet.paperSize, standard: settings.standard)
        let notes = sheet.notes
        guard !notes.isEmpty else { return picture }
        let standard = settings.standard
        let style = DrawingStyle.of(standard)
        let symbols = SymbolStyle.of(standard)
        let h = style.notesHeight(for: sheet.size)
        let origin = TitleBlockLayout.origin(for: sheet, standard: standard)
        let top = base ?? origin.y + TitleBlockLayout.height
        let right = origin.x + TitleBlockLayout.width
        var ceiling = top
        if let surface = notes.surface {
            let apexY = top + symbols.notesGap
            let stand = Stand(
                apexY: apexY, right: right, h: h, parentheses: hasSurfaceSymbols(sheet), style: style, format: format)
            ceiling = standSurface(surface, stand, into: &picture)
        }
        let lines = notes.lines + (notes.edgeBreak.map { [edgeBreakText($0, standard: standard, format: format)] } ?? [])
        let pitch = AnnotationStyle.of(standard).linePitch * h
        let bottom = (notes.surface == nil ? top : ceiling) + symbols.notesGap
        for (index, line) in lines.enumerated() {
            let text = "\(index + 1). " + line
            let baseline = bottom + Double(lines.count - 1 - index) * pitch
            picture.texts.append(
                SheetText(
                    run: DrawingText.layout(text, height: h), original: text, origin: Vector2(origin.x, baseline), height: h,
                    layer: .text))
        }
        return picture
    }

    static func edgeBreakText(_ value: EdgeBreak, standard: DrawingStandard, format: NumberFormat) -> String {
        let low = GDTNumber.tolerance(value.minimum, format: format)
        let high = GDTNumber.tolerance(value.maximum, format: format)
        let same = low == high
        switch standard {
        case .iso: return same ? "Break all sharp edges \(low)." : "Break all sharp edges \(low) to \(high)."
        case .asme: return same ? "BREAK ALL SHARP EDGES \(low)" : "BREAK ALL SHARP EDGES \(low)-\(high)"
        }
    }

    private static func hasSurfaceSymbols(_ sheet: DrawingSheet) -> Bool {
        sheet.annotations.contains { if case .surfaceTexture = $0.kind { true } else { false } }
    }

    /// Where and how the general surface requirement stands.
    private struct Stand {
        var apexY: Double
        var right: Double
        var h: Double
        var parentheses: Bool
        var style: DrawingStyle
        var format: NumberFormat
    }

    /// Draws the requirement right-aligned to `stand.right`, its apex `stand.apexY`; returns the top of what it drew.
    private static func standSurface(_ surface: SurfaceRequirement, _ stand: Stand, into picture: inout SheetPicture) -> Double {
        let (apexY, right, h, style, format) = (stand.apexY, stand.right, stand.h, stand.style, stand.format)
        let symbols = SymbolStyle.of(style.standard)
        let gap = symbols.surfaceTextGap * h
        var edge = right
        var texts: [(String, Double)] = []
        var strokes: [[SheetSegment]] = []
        if stand.parentheses {
            let close = DrawingText.layout(")", height: h), open = DrawingText.layout("(", height: h)
            texts.append((")", edge - close.width))
            edge -= close.width + gap
            var basic = AnnotationDrawing(segments: DrawingSymbols.surface(.any, apex: Vector2(0, apexY), h: h, extension: nil))
            basic.fitFrame()
            let shift = edge - basic.frame.max.x
            strokes.append(basic.segments.map { $0.transformed(scale: 1, offset: Vector2(shift, 0)) })
            edge = basic.frame.min.x + shift - gap
            texts.append(("(", edge - open.width))
            edge -= open.width + gap
        }
        var main = SurfaceLayout.requirement(surface, apex: Vector2(0, apexY), h: h, format: format)
        let shift = edge - main.frame.max.x
        main.segments = main.segments.map { $0.transformed(scale: 1, offset: Vector2(shift, 0)) }
        for index in main.texts.indices { main.texts[index].origin.x += shift }
        var topY = main.frame.max.y
        for (text, x) in texts {
            picture.texts.append(
                SheetText(run: DrawingText.layout(text, height: h), original: text, origin: Vector2(x, apexY), height: h, layer: .text))
            topY = Swift.max(topY, apexY + h)
        }
        for group in strokes + [main.segments] {
            for segment in group {
                picture.strokes.append(SheetStroke(segments: [segment], width: style.thin, layer: .text))
            }
        }
        for text in main.texts {
            picture.texts.append(
                SheetText(run: text.run, original: text.original, origin: text.origin, height: text.height, layer: .text))
        }
        return topY
    }
}

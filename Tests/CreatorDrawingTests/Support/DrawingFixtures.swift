import CreatorGeometry
import CreatorKernel

@testable import CreatorDrawing

/// A fixed A4 sheet (portrait, 210 x 297 mm) with a box view and a cylinder view and a title block, built by hand from
/// strokes and texts: no kernel. Shared by the PDF and DXF tests.
enum DrawingFixtures {
    static let titleBlockText = "Ø20 ±0.1 µm 90°"

    static func text(_ string: String, at origin: Vector2, height: Double, view: ViewID? = nil) -> SheetText {
        SheetText(run: DrawingText.layout(string, height: height), original: string, origin: origin, height: height, view: view)
    }

    static func a4Sheet() -> SheetPicture {
        let style = DrawingStyle.iso
        var picture = SheetPicture(size: Vector2(210, 297))
        picture.strokes.append(
            SheetStroke(
                segments: [.polyline([Vector2(20, 10), Vector2(200, 10), Vector2(200, 287), Vector2(20, 287), Vector2(20, 10)])],
                width: style.frame, layer: .frame))
        // The box view: a 40 x 30 rectangle with a hidden inner line.
        picture.strokes.append(
            SheetStroke(
                segments: [.polyline([Vector2(40, 200), Vector2(80, 200), Vector2(80, 230), Vector2(40, 230), Vector2(40, 200)])],
                width: style.thick, layer: .visible))
        picture.strokes.append(
            SheetStroke(segments: [.line(Vector2(45, 205), Vector2(75, 205))], width: style.thin, pattern: .hidden, layer: .hidden))
        // The cylinder view: its end as a circle with centre lines, and a side outline.
        picture.strokes.append(
            SheetStroke(
                segments: [.arc(center: Vector2(130, 215), radius: 10, start: 0, sweep: 2 * .pi)], width: style.thick,
                layer: .visible))
        picture.strokes.append(
            SheetStroke(
                segments: [.line(Vector2(115, 215), Vector2(145, 215)), .line(Vector2(130, 200), Vector2(130, 230))],
                width: style.thin, layer: .center))
        let halfEllipse = SheetSegment.ellipse(
            center: Vector2(130, 150), majorAxis: Vector2(1, 0), majorRadius: 12, minorRadius: 5, start: 0, sweep: .pi)
        picture.strokes.append(
            SheetStroke(
                segments: [halfEllipse],
                width: style.thick, layer: .visible))
        picture.texts.append(text("A", at: Vector2(40, 235), height: style.viewLabelHeight))
        picture.texts.append(text("Ω-Bracket →", at: Vector2(25, 20), height: style.titleHeight))
        picture.texts.append(text(titleBlockText, at: Vector2(25, 40), height: style.notesHeight(for: .a4)))
        picture.texts.append(text("a(b)c\\d", at: Vector2(25, 50), height: style.notesHeight(for: .a4)))
        return picture
    }
}

extension DrawingFixtures {
    /// A4 with a hatched rectangle, a stepped cutting line with its arrows and letters, and a detail circle. Built from the
    /// marks and hatch alone (no `sin` or `cos`), so its bytes are the same on every platform.
    static func hatchedSheet(standard: DrawingStandard = .iso) -> SheetPicture {
        let style = DrawingStyle.of(standard)
        let (parent, section) = (ViewID(), ViewID())
        var picture = SheetPicture(size: Vector2(210, 297), standard: standard)
        let region = HatchRegion(
            part: 0, edges: [[Vector2(40, 100), Vector2(120, 100), Vector2(120, 140), Vector2(40, 140)]])
        picture.strokes += HatchPattern.strokes(
            [region], mapping: ViewMapping(scale: 1, offset: .zero), clips: [], spacing: style.hatchSpacing(for: .a4),
            width: style.thin, view: section)
        let frame = StandardOrientation.front.frame
        let cutter = SectionCutter(
            frame: frame, points: [Vector2(30, 200), Vector2(70, 200), Vector2(70, 215), Vector2(110, 215)],
            viewing: Vector2(0, 1))
        let marks = SectionMarks.cuttingLine(
            cutter, letter: "A", mapping: ViewMapping(scale: 1, offset: .zero), parent: parent, mark: section,
            standard: standard)
        let circle = SectionMarks.detailCircle(
            DetailCircle(parent: parent, center: Vector2(150, 220), radius: 10), letter: "B",
            mapping: ViewMapping(scale: 1, offset: .zero), parent: parent, mark: section, standard: standard)
        for pieces in [marks, circle] {
            picture.strokes += pieces.strokes
            picture.fills += pieces.fills
            picture.texts += pieces.texts
        }
        return picture
    }
}

extension DrawingFixtures {
    /// A4 with every kind of symbol, laid out by hand (no kernel, no `sin` or `cos`): a frame of every modifier, a composite frame, a
    /// datum on a line and on a dimension, two surface symbols and the sheet's notes with an edge break and a general surface.
    static func symbolsSheet(standard: DrawingStandard = .iso) -> SheetPicture {
        let parts = symbolsSheetParts(standard: standard)
        var picture = parts.symbols
        picture.append(parts.notes)
        return picture
    }

    /// The symbols of `symbolsSheet` and its sheet notes, apart.
    static func symbolsSheetParts(standard: DrawingStandard = .iso) -> (symbols: SheetPicture, notes: SheetPicture) {
        let style = DrawingStyle.of(standard)
        let h = style.notesHeight(for: .a4)
        let format = NumberFormat(units: .millimetres, standard: standard, decimalSign: .point)
        let annotationStyle = AnnotationStyle.of(standard)
        var picture = SheetPicture(size: Vector2(210, 297), standard: standard)
        func add(_ drawing: AnnotationDrawing) {
            for segment in drawing.segments {
                picture.strokes.append(SheetStroke(segments: [segment], width: style.thin, layer: .dimension))
            }
            for box in drawing.boxes {
                picture.strokes.append(SheetStroke(segments: [.polyline(box)], width: style.thin, layer: .dimension))
            }
            for fill in drawing.fills { picture.fills.append(SheetFill(points: fill, layer: .dimension)) }
            for text in drawing.texts {
                picture.texts.append(
                    SheetText(
                        run: text.run, original: text.original, origin: text.origin, height: text.height, layer: .dimension,
                        angle: text.angle))
            }
        }
        let frames = symbolFrames()
        for (index, frame) in frames.enumerated() {
            add(FrameLayout.draw(
                frame, topLeft: Vector2(30, 260 - Double(index) * 20), h: h, format: format, standard: standard))
        }
        add(DatumLayout.onLine(
            letter: "A", foot: Vector2(40, 150), along: Vector2(1, 0), distance: 8, edgeEnds: nil, h: h, style: annotationStyle))
        add(DatumLayout.onDimensionLine(
            letter: "B", end: Vector2(120, 150), other: Vector2(80, 150), distance: 8, h: h, style: annotationStyle))
        let feature = LeaderEnd(target: .point(Vector2(0, 0)), hint: Vector2(0, 0))
        let ground = SurfaceTexture(
            requirement: SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 1.6), lay: .perpendicular,
            feature: feature)
        let raw = SurfaceTexture(
            requirement: SurfaceRequirement(process: .removalProhibited), feature: feature, offset: Vector2(6, 8))
        add(SurfaceLayout.draw(ground, foot: Vector2(40, 100), along: Vector2(1, 0), h: h, format: format, style: annotationStyle))
        add(SurfaceLayout.draw(raw, foot: Vector2(100, 100), along: Vector2(1, 0), h: h, format: format, style: annotationStyle))
        let surface = DrawingAnnotation(view: nil, kind: .surfaceTexture(ground))
        let sheet = DrawingSheet(
            name: "S", size: .a4, orientation: .portrait,
            annotations: [surface],
            notes: SheetNotes(
                lines: ["Deburr.", "Material per drawing."], edgeBreak: EdgeBreak(minimum: 0.2, maximum: 0.5),
                surface: SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 3.2)))
        let notes = SheetNotesLayout.picture(for: sheet, settings: DrawingSettings(standard: standard), format: format)
        return (picture, notes)
    }

    /// A frame of every modifier, a composite one, and two plain ones.
    private static func symbolFrames() -> [FeatureControlFrame] {
        let attachment = SymbolAttachment.feature(LeaderEnd(target: .point(Vector2(0, 0)), hint: Vector2(0, 0)))
        let modifiers = FeatureControlFrame(
            characteristic: .position,
            rows: [
                ToleranceRow(
                    zone: .diameter, value: 0.1, material: .maximum, freeState: true, tangentPlane: true,
                    projected: ProjectedZone(length: 20),
                    datums: [DatumReference(letter: "A", material: .least), DatumReference(letter: "B", material: .maximum)]),
            ], attachment: attachment)
        let composite = FeatureControlFrame(
            characteristic: .surfaceProfile,
            rows: [
                ToleranceRow(value: 0.5, datums: [DatumReference(letter: "A")]),
                ToleranceRow(value: 0.2, datums: [DatumReference(letter: "A")]),
            ], attachment: attachment)
        let flat = FeatureControlFrame(
            characteristic: .flatness, rows: [ToleranceRow(value: 0.05)], attachment: attachment)
        let runout = FeatureControlFrame(
            characteristic: .totalRunout, rows: [ToleranceRow(value: 0.1, datums: [DatumReference(letter: "A")])],
            attachment: attachment)
        return [modifiers, composite, flat, runout]
    }
}

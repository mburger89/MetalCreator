import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite struct FrameLayoutTests {
    let h = 2.5
    let format = NumberFormat(units: .millimetres, standard: .iso, decimalSign: .point)
    let attachment = SymbolAttachment.dimension(AnnotationID())

    func frame(
        _ characteristic: GeometricCharacteristic, rows: [ToleranceRow]
    ) -> FeatureControlFrame {
        FeatureControlFrame(characteristic: characteristic, rows: rows, attachment: attachment)
    }

    func draw(_ frame: FeatureControlFrame, standard: DrawingStandard = .iso) -> AnnotationDrawing {
        let format = NumberFormat(units: .millimetres, standard: standard, decimalSign: .point)
        return FrameLayout.draw(frame, topLeft: Vector2(0, 0), h: h, format: format, standard: standard)
    }

    @Test func aSingleRowFrame() {
        let flat = frame(.flatness, rows: [ToleranceRow(value: 0.05)])
        let drawing = draw(flat)
        let columns = FrameLayout.columns(of: flat, h: h, format: format)
        #expect(columns.count == 2 && columns[0] == 5)
        let value = DrawingText.layout("0.05", height: h)
        #expect(abs(columns[1] - (value.width + 2 * 1.25)) <= 1e-12)
        #expect(abs(drawing.frame.max.y - drawing.frame.min.y - 5) <= 1e-12)
        #expect(drawing.texts.count == 1 && drawing.texts[0].origin.y == -5 + 1.25 + 0)
        #expect(FrameLayout.size(of: flat, h: h, format: format, standard: .iso) == Vector2(columns[0] + columns[1], 5))
        // The glyph cell is 5 by 5: its glyph sits inside x 1.25...3.75, y -3.75...-1.25.
        let glyph = DrawingSymbols.characteristic(.flatness, origin: Vector2(1.25, -3.75), h: h)
        for segment in glyph { #expect(drawing.segments.contains(segment)) }
    }

    @Test func datumCellsAreAtLeastTwoH() {
        let rows = [ToleranceRow(value: 0.1, datums: [DatumReference(letter: "A")])]
        let columns = FrameLayout.columns(of: frame(.perpendicularity, rows: rows), h: h, format: format)
        #expect(columns.count == 3 && columns[2] == 5)
    }

    @Test func modifiersComeInOrder() {
        let row = ToleranceRow(
            zone: .diameter, value: 0.1, material: .maximum, freeState: true, tangentPlane: true, projected: ProjectedZone(length: 20))
        let drawing = draw(frame(.parallelism, rows: [row]))
        let pieces = FrameLayout.pieces(of: row, format: format)
        #expect(pieces == [.text("Ø0.1"), .circled("M"), .circled("F"), .circled("T"), .circled("P"), .text("20")])
        let centres = drawing.segments.compactMap { segment -> Double? in
            if case let .arc(center, _, _, _) = segment, center.y == -h { return center.x }
            return nil
        }
        #expect(centres.count == 4 && centres == centres.sorted())
        for index in 1..<4 { #expect(abs(centres[index] - centres[index - 1] - 1.5 * h) <= 1e-9) }  // 1.2h advance + 0.3h gap
        let last = drawing.texts.last
        #expect(last?.original == "20")
        #expect(abs((last?.origin.x ?? 0) - (centres[3] + 0.6 * h + 0.3 * h)) <= 1e-9)
    }

    @Test func aDiameterZoneWritesØ() {
        let drawing = draw(frame(.position, rows: [ToleranceRow(zone: .diameter, value: 0.1)]))
        #expect(drawing.texts.first?.original.hasPrefix("Ø") == true)
    }

    @Test func asmeCompositeSpansTheSymbol() {
        let rows = [
            ToleranceRow(value: 0.5, datums: [DatumReference(letter: "A")]), ToleranceRow(value: 0.2)
        ]
        let composite = frame(.surfaceProfile, rows: rows)
        let drawing = draw(composite, standard: .asme)
        let glyph = DrawingSymbols.characteristic(.surfaceProfile, origin: Vector2(1.25, -2 * h - h / 2), h: h)
        for segment in glyph { #expect(drawing.segments.contains(segment)) }
        #expect(drawing.texts.count == 3)
        #expect(abs(drawing.frame.max.y - drawing.frame.min.y - 4 * h) <= 1e-12)
        let cell = drawing.segments.contains(
            .polyline([Vector2(5, 0), Vector2(0, 0), Vector2(0, -10), Vector2(5, -10), Vector2(5, 0)]))
        #expect(cell)
    }

    @Test func isoCompositeStacksTwoFrames() {
        let rows = [ToleranceRow(value: 0.5), ToleranceRow(value: 0.2)]
        let drawing = draw(frame(.lineProfile, rows: rows))
        let first = DrawingSymbols.characteristic(.lineProfile, origin: Vector2(1.25, -3.75), h: h)
        let second = DrawingSymbols.characteristic(.lineProfile, origin: Vector2(1.25, -8.75), h: h)
        for segment in first + second { #expect(drawing.segments.contains(segment)) }
    }

    @Test func compositeColumnsAlign() {
        let rows = [
            ToleranceRow(value: 0.5, datums: [DatumReference(letter: "A"), DatumReference(letter: "B")]),
            ToleranceRow(value: 0.25, datums: [DatumReference(letter: "A")]),
        ]
        let composite = frame(.position, rows: rows)
        let drawing = draw(composite)
        let columns = FrameLayout.columns(of: composite, h: h, format: format)
        func boundaries(top: Double) -> [Double] {
            drawing.segments.compactMap { segment in
                if case let .line(a, b) = segment, a.y == top, b.y == top - 5 { return a.x }
                return nil
            }
        }
        let first = boundaries(top: 0), second = boundaries(top: -5)
        // Row 1 has dividers after columns 0, 1 and 2; row 2 after 0 and 1; shared widths put them at equal x.
        #expect(first.count == 3 && second.count == 2)
        #expect(second == Array(first.prefix(2)))
        #expect(abs(first[2] - (columns[0] + columns[1] + columns[2])) <= 1e-12)
    }

    @Test func linesAreThinOnTheDimensionLayer() {
        // Layer and weight belong to the composer: a frame has only lines, texts and no fill or basic box of its own.
        let drawing = draw(frame(.flatness, rows: [ToleranceRow(value: 0.05)]))
        #expect(drawing.fills.isEmpty && drawing.boxes.isEmpty && !drawing.segments.isEmpty)
    }

    @Test func theLeaderMeetsTheNearerSide() {
        let rect = Rect2D(min: Vector2(10, 0), max: Vector2(30, 5))
        let style = AnnotationStyle.iso
        let left = FrameLayout.leader(from: Vector2(0, 20), toFrameAt: rect, rowHeight: 5, style: style)
        #expect(left.segments.contains(.line(Vector2(10 - style.shoulder, 2.5), Vector2(10, 2.5))))
        let right = FrameLayout.leader(from: Vector2(50, 20), toFrameAt: rect, rowHeight: 5, style: style)
        #expect(right.segments.contains(.line(Vector2(30 + style.shoulder, 2.5), Vector2(30, 2.5))))
    }

    @Test func plainTexts() {
        let rows = [
            ToleranceRow(
                zone: .diameter, value: 0.1, material: .maximum,
                datums: [DatumReference(letter: "A"), DatumReference(letter: "B", material: .maximum)]),
        ]
        #expect(frame(.position, rows: rows).plainText(format: format) == "Position Ø0.1 (M) | A | B (M)")
        let composite = frame(.position, rows: rows + [ToleranceRow(zone: .diameter, value: 0.05)])
        #expect(composite.plainText(format: format) == "Position Ø0.1 (M) | A | B (M) / Ø0.05")
        let projected = ToleranceRow(value: 0.1, projected: ProjectedZone(length: 20))
        #expect(frame(.parallelism, rows: [projected]).plainText(format: format) == "Parallelism 0.1 (P) 20")
        #expect(DatumFeature(letter: "A", attachment: attachment).plainText == "Datum A")
        let texture = SurfaceTexture(
            requirement: SurfaceRequirement(parameter: .ra, value: 1.6), lay: .crossed,
            feature: LeaderEnd(target: .point(Vector2(0, 0)), hint: .zero))
        #expect(texture.plainText(format: format) == "Surface texture Ra 1.6 lay X")
    }

    @Test func plainTextsFollowTheSheetsFormat() {
        let inches = DimensionNumberTests.format(.inches, .asme, precision: 3)
        let comma = NumberFormat(units: .millimetres, standard: .iso, decimalSign: .comma)
        let flat = frame(.flatness, rows: [ToleranceRow(value: 0.127)])
        #expect(flat.plainText(format: inches) == "Flatness .005")
        #expect(flat.plainText(format: comma) == "Flatness 0,127")
        let texture = SurfaceTexture(
            requirement: SurfaceRequirement(parameter: .ra, value: 1.6), lay: nil,
            feature: LeaderEnd(target: .point(Vector2(0, 0)), hint: .zero))
        #expect(texture.plainText(format: comma) == "Surface texture Ra 1,6")
        #expect(texture.plainText(format: inches).contains("Ra 63"))
    }
}

import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing
@testable import CreatorGraph

@Suite struct DXFWriterTests {
    private let style = DrawingStyle.iso
    private let a4 = Rect2D(min: .zero, max: Vector2(210, 297))

    private func fixture() -> DXFOutput {
        let sheet = DrawingFixtures.a4Sheet()
        return DXFWriter.write(strokes: sheet.strokes, texts: sheet.texts, extent: a4, style: style)
    }

    private func read(_ output: DXFOutput) throws -> DXFReader { try DXFReader(data: output.data) }

    private func strokeOnly(_ segments: [SheetSegment], layer: DrawingLayer = .visible) -> DXFOutput {
        DXFWriter.write(
            strokes: [SheetStroke(segments: segments, width: 0.5, layer: layer)], texts: [], extent: a4, style: style)
    }

    private func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> ProjectedLine {
        ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(Vector2(x1, y1), Vector2(x2, y2)), source: nil)
    }

    private func view() -> DrawingView {
        DrawingView(kind: .base, source: NodeID(), orientation: .standard(.front), center: Vector2(150, 150))
    }

    @Test func theHeaderIsR2000InMillimetres() throws {
        let reader = try read(fixture())
        #expect(reader.headerValue("$ACADVER") == "AC1015")
        #expect(reader.headerValue("$INSUNITS") == "4")
        #expect(reader.headerValue("$DWGCODEPAGE") == "ANSI_1252")
        let seed = try #require(reader.handseed)
        let largest = reader.handles.compactMap { Int($0, radix: 16) }.max() ?? 0
        #expect(seed > largest)
        #expect(seed == largest + 1)
    }

    @Test func theObjectsAreWhatAutoCADExpects() throws {
        let sheetReader = try read(fixture())
        #expect(sheetReader.objectProblems == [])
        let projection = Projection2D(lines: [line(5, 7, 25, 7), line(25, 7, 25, 17)])
        let viewReader = try read(DXFWriter.view(projection, view: view(), style: style))
        #expect(viewReader.objectProblems == [])
        #expect(!viewReader.entities.isEmpty)
    }

    @Test func replacedTextsAreReported() throws {
        var picture = SheetPicture(size: Vector2(210, 297))
        picture.texts = [
            DrawingFixtures.text("Ω-Bracket →", at: Vector2(10, 10), height: 7),
            DrawingFixtures.text("Ω-Bracket →", at: Vector2(10, 30), height: 7),
        ]
        let output = DXFWriter.sheet(picture, style: style)
        #expect(output.replacedTexts == ["Ω-Bracket →"])
        let texts = try read(output).entities.filter { $0.type == "TEXT" }
        #expect(texts.allSatisfy { $0.first(1) == "?-Bracket ?" })
        #expect(texts.count == 2)
    }

    @Test func theEightLayersExist() throws {
        let reader = try read(fixture())
        let names = ["VISIBLE", "HIDDEN", "TANGENT", "CENTER", "DIMENSION", "TEXT", "HATCH", "FRAME"]
        for name in names { #expect(reader.layer(name) != nil, "\(name)") }
        #expect(reader.layer("0") != nil)
        #expect(reader.layers.count == 9)
        #expect(reader.layer("HIDDEN")?.first(6) == "DASHED")
        #expect(reader.layer("CENTER")?.first(6) == "CENTER")
        #expect(reader.layer("VISIBLE")?.first(6) == "Continuous")
        let weights = names.map { reader.layer($0)?.first(370) }
        #expect(weights == ["50", "25", "25", "25", "25", "25", "25", "70"])
        #expect(reader.layers.allSatisfy { $0.first(62) == "7" })
        let types = reader.lineTypes.compactMap { $0.first(2) }
        #expect(types == ["ByBlock", "ByLayer", "Continuous", "DASHED", "CENTER"])
        let dashed = try #require(reader.lineTypes.first { $0.first(2) == "DASHED" })
        #expect(dashed.all(49) == ["3", "-1.5"])
        let center = try #require(reader.lineTypes.first { $0.first(2) == "CENTER" })
        #expect(center.all(49) == ["6", "-0.75", "0", "-0.75"])
        let asme = try read(DXFWriter.write(strokes: [], texts: [], extent: a4, style: .asme))
        #expect(asme.layer("VISIBLE")?.first(370) == "60")
        #expect(asme.layer("TEXT")?.first(370) == "30")
    }

    @Test func linesArcsCirclesEllipsesAreTrue() throws {
        let tau = 2 * Double.pi
        let ratio = 1 / 3.0.squareRoot()
        let reader = try read(
            strokeOnly([
                .line(Vector2(1, 2), Vector2(4, 6)),
                .arc(center: Vector2(10, 10), radius: 5, start: 0, sweep: tau),
                .arc(center: Vector2(20, 10), radius: 5, start: 0, sweep: .pi),
                .arc(center: Vector2(30, 10), radius: 5, start: .pi / 2, sweep: -.pi / 2),
                .ellipse(
                    center: Vector2(40, 10), majorAxis: Vector2(1, 0), majorRadius: 6, minorRadius: 6 * ratio, start: 0,
                    sweep: tau),
                .polyline([Vector2(0, 0), Vector2(5, 0), Vector2(5, 5)]),
            ]))
        let types = reader.entities.map(\.type)
        #expect(types == ["LINE", "CIRCLE", "ARC", "ARC", "ELLIPSE", "LWPOLYLINE"])
        let e = reader.entities
        #expect(e[0].all(10) == ["1"] && e[0].all(20) == ["2"] && e[0].all(11) == ["4"] && e[0].all(21) == ["6"])
        #expect(e[1].number(40) == 5 && e[1].number(10) == 10)
        #expect(e[2].number(50) == 0 && e[2].number(51) == 180)
        // A clockwise quarter from 90 degrees is the counter-clockwise quarter from 0 to 90.
        #expect(e[3].number(50) == 0 && e[3].number(51) == 90)
        let ellipse = e[4]
        let ellipseRatio = try #require(ellipse.number(40))
        #expect(abs(ellipseRatio - ratio) < 1e-8)
        #expect(ellipse.number(11) == 6 && ellipse.number(21) == 0)
        #expect(ellipse.number(41) == 0 && abs((ellipse.number(42) ?? 0) - tau) < 1e-8)
        #expect(e[5].number(90) == 3)
        #expect(e[5].all(10) == ["0", "5", "5"] && e[5].all(20) == ["0", "0", "5"])
    }

    @Test func layersFollowTheLineClass() throws {
        let projection = Projection2D(lines: [
            line(0, 0, 10, 0),
            ProjectedLine(visibility: .hidden, lineClass: .sharp, curve: .line(Vector2(0, 1), Vector2(10, 1)), source: nil),
            ProjectedLine(visibility: .visible, lineClass: .smooth, curve: .line(Vector2(0, 2), Vector2(10, 2)), source: nil),
        ])
        var shown = view()
        shown.showsHidden = true
        shown.showsTangent = true
        let reader = try read(DXFWriter.view(projection, view: shown, style: style))
        #expect(reader.entities.map { $0.layer ?? "" } == ["VISIBLE", "HIDDEN", "TANGENT"])
        #expect(reader.entities.map { $0.first(370) ?? "" } == ["50", "25", "25"])
        let sheet = try read(fixture())
        let frames = sheet.entities.filter { $0.layer == "FRAME" }
        #expect(!frames.isEmpty)
        #expect(sheet.entities.filter { $0.type == "TEXT" }.allSatisfy { $0.layer == "TEXT" })
        #expect(sheet.entities.contains { $0.layer == "HIDDEN" })
        #expect(sheet.entities.contains { $0.layer == "CENTER" })
    }

    @Test func symbolsUseDXFCodes() throws {
        var picture = SheetPicture(size: Vector2(210, 297))
        picture.texts = [
            DrawingFixtures.text("Ø20 ±0.1 90°", at: Vector2(10, 10), height: 3.5),
            DrawingFixtures.text("µ é 100%", at: Vector2(10, 20), height: 3.5),
        ]
        let reader = try read(DXFWriter.sheet(picture, style: style))
        let texts = reader.entities.filter { $0.type == "TEXT" }.compactMap { $0.first(1) }
        #expect(texts == ["%%c20 %%p0.1 90%%d", "\\U+00B5 \\U+00E9 100%%%"])
        #expect(reader.entities.first?.number(40) == 3.5)
    }

    @Test func sheetAndViewModesMeasureTrue() throws {
        let projection = Projection2D(lines: [line(5, 7, 105, 7)])
        var onSheet = view()
        onSheet.scale = nil
        let sheet = DrawingSheet(
            name: "S", scale: DrawingScale(numerator: 1, denominator: 2), views: [onSheet])
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [onSheet.id: ViewContent(projection: projection)],
            facts: TitleBlockFacts())
        let sheetReader = try read(DXFWriter.sheet(picture, style: style))
        let sheetLine = try #require(sheetReader.entities.first { $0.type == "LINE" && $0.layer == "VISIBLE" })
        #expect(abs((sheetLine.number(11) ?? 0) - (sheetLine.number(10) ?? 0) - 50) < 1e-6)
        #expect(sheetReader.entities.contains { $0.layer == "FRAME" })

        let viewReader = try read(DXFWriter.view(projection, view: onSheet, style: style))
        let only = try #require(viewReader.entities.first)
        #expect(viewReader.entities.count == 1)
        #expect(only.number(10) == 5 && only.number(11) == 105 && only.number(20) == 7 && only.number(21) == 7)
        #expect(!viewReader.entities.contains { $0.layer == "FRAME" })

        let top = Projection2D(lines: [line(5, 7, 25, 7), line(25, 7, 25, 17), line(25, 17, 5, 17), line(5, 17, 5, 7)])
        let topReader = try read(DXFWriter.view(top, view: onSheet, style: style))
        let xs = topReader.entities.flatMap { $0.all(10) + $0.all(11) }.compactMap(Double.init)
        let ys = topReader.entities.flatMap { $0.all(20) + $0.all(21) }.compactMap(Double.init)
        #expect(xs.min() == 5 && xs.max() == 25 && ys.min() == 7 && ys.max() == 17)
        #expect(DXFWriter.view(top, view: onSheet, style: style).replacedTexts.isEmpty)
    }

    @Test func handlesAreUniqueAndOwned() throws {
        for output in [fixture(), DXFWriter.view(Projection2D(lines: [line(0, 0, 1, 1)]), view: view(), style: style)] {
            let reader = try read(output)
            #expect(reader.duplicateHandles == [])
            #expect(reader.danglingReferences == [])
            #expect(reader.handles.allSatisfy { Int($0, radix: 16).map { $0 >= 0x20 } == true })
            #expect(reader.entities.allSatisfy { $0.first(330) != nil })
        }
    }

    @Test func writingIsDeterministic() {
        #expect(fixture().data == fixture().data)
        let text = String(bytes: fixture().data, encoding: .utf8) ?? ""
        #expect(!text.contains("\r"))
        #expect(text.hasSuffix("0\nEOF\n"))
    }

    @Test func theFixturesDigestIsPinned() {
        let digest = SHA256.hash(fixture().data)
            .map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
        #expect(digest == "916e7937e7f7b5b7cf478ace06fdba160cc68e459d8cd17be7758823a45bb853")
    }
}

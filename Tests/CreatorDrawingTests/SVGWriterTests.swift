import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing
@testable import CreatorGraph

@Suite("SVG writer")
struct SVGWriterTests {
    private func write(_ page: SheetPicture, title: String = "Test") -> SVGOutput { SVGWriter.write(page, title: title) }
    private func read(_ output: SVGOutput) throws -> SVGStructureReader { try SVGStructureReader(data: output.data) }

    @Test func theSheetIsInMillimetres() throws {
        let reader = try read(write(SheetPicture(size: Vector2(420, 297))))
        let root = try #require(reader.elements.first { $0.name == "svg" })
        #expect(root.attribute("width") == "420mm" && root.attribute("height") == "297mm")
        #expect(root.attribute("viewBox") == "0 0 420 297")
        #expect(reader.elements(named: "g").first?.attribute("transform") == "matrix(1 0 0 -1 0 297)")
        #expect(reader.elements(named: "title").first?.text == "Test")
    }

    @Test func layersInOrder() throws {
        let reader = try read(write(DrawingFixtures.assemblySheet()))
        let order = DrawingLayer.allCases.map(\.rawValue)
        let ids = reader.groupIDs
        #expect(ids == order.filter { ids.contains($0) } && ids.count >= 5)
        #expect(!ids.contains("TANGENT") && !ids.contains("HATCH"), "empty layers are absent")
    }

    @Test func strokesMatchThePDFsPath() throws {
        var page = SheetPicture(size: Vector2(210, 297))
        page.strokes = [
            SheetStroke(segments: [.line(Vector2(1, 2), Vector2(3, 4))], width: 0.5, layer: .visible),
            SheetStroke(segments: [.polyline([Vector2(0, 0), Vector2(5, 0), Vector2(5, 5)])], width: 0.25, layer: .visible),
            SheetStroke(
                segments: [.arc(center: Vector2(50, 50), radius: 10, start: 0, sweep: .pi / 2)], width: 0.5, layer: .visible),
        ]
        let paths = try read(write(page)).elements(named: "path").compactMap { $0.attribute("d") }
        #expect(paths[0] == "M1 2 L3 4")
        #expect(paths[1] == "M0 0 L5 0 L5 5")
        #expect(paths[2].hasPrefix("M60 50 C") && !paths[2].contains("L"))
        let pdf = pdfText(PDFWriter.write([page], title: "T").data)
        let numbers = paths[2].split(whereSeparator: { $0 == " " || $0 == "C" || $0 == "M" }).map(String.init)
        for number in numbers { #expect(pdf.contains(number)) }
    }

    @Test func dashesFollowTheStandard() throws {
        var page = SheetPicture(size: Vector2(210, 297))
        page.strokes = [SheetStroke(segments: [.line(Vector2(0, 0), Vector2(9, 0))], width: 0.25, pattern: .hidden, layer: .hidden)]
        let iso = try read(write(page)).elements(named: "path").first
        #expect(iso?.attribute("stroke-dasharray") == "3 1.5")
        #expect(iso?.attribute("fill") == "none" && iso?.attribute("stroke-linecap") == "butt")
        page.strokes[0].pattern = .centre
        let chain = try read(write(page)).elements(named: "path").first
        let expected = DrawingStyle.iso.centreDash.map { PDFNumber.format($0, decimals: 4) }.joined(separator: " ")
        #expect(chain?.attribute("stroke-dasharray") == expected)
    }

    @Test func textsCarryTheirWidth() throws {
        var page = SheetPicture(size: Vector2(210, 297))
        page.texts = [
            DrawingFixtures.text("Ø20", at: Vector2(10, 10), height: 3.5), DrawingFixtures.text("a<b", at: Vector2(10, 20), height: 3.5),
        ]
        let output = write(page)
        let reader = try read(output)
        let texts = reader.elements(named: "text")
        #expect(texts[0].text == "Ø20" && texts[1].text == "a<b")
        #expect(texts[0].attribute("textLength") == PDFNumber.format(page.texts[0].run.width, decimals: 4))
        #expect(texts[0].attribute("transform") == "matrix(1 0 0 -1 10 10)")
        let raw = (String(bytes: output.data, encoding: .utf8) ?? "")
        #expect(raw.contains(">Ø20</text>") && raw.contains(">a&lt;b</text>"))
    }

    @Test func theLogoIsAPNG() throws {
        let page = DrawingFixtures.assemblySheet()
        let image = try #require(try read(write(page)).elements(named: "image").first)
        let uri = try #require(image.attribute("href"))
        #expect(uri.hasPrefix("data:image/png;base64,"))
        let decoded = try #require(Data(base64Encoded: String(uri.dropFirst("data:image/png;base64,".count))))
        #expect(decoded == GreyPNG.encode(DrawingFixtures.logo))
        #expect(image.attribute("preserveAspectRatio") == "none")
        #expect(image.attribute("x") == "30" && image.attribute("y") == "20")
        #expect(image.attribute("width") == "4" && image.attribute("height") == "3")
        #expect(image.attribute("xlink:href") == uri)
    }

    @Test func theLogoIsUpright() throws {
        var page = SheetPicture(size: Vector2(420, 297))
        page.images = [SheetImage(rect: Rect2D(min: Vector2(10, 20), max: Vector2(14, 23)), pixels: DrawingFixtures.logo)]
        let image = try #require(try read(write(page)).elements(named: "image").first)
        #expect(image.attribute("transform") == "matrix(1 0 0 -1 0 43)")
        // Compose the image's own matrix with the group's (sheet y 297 - y): local y0 = 20 is where SVG draws row 0.
        func sheetY(ofLocal y: Double) -> Double { 43 - y }
        #expect(sheetY(ofLocal: 20) == 23, "row 0 lands on the rect's top")
        #expect(sheetY(ofLocal: 23) == 20, "the last row on the bottom")
    }

    @Test func noticesAreNotWritten() throws {
        var page = SheetPicture(size: Vector2(210, 297))
        var notice = DrawingFixtures.text("Careful", at: Vector2(10, 10), height: 3.5)
        notice.isNotice = true
        page.texts = [notice]
        let output = write(page)
        #expect(!(String(bytes: output.data, encoding: .utf8) ?? "").contains("Careful"))
        #expect(try read(output).elements(named: "text").isEmpty)
    }

    @Test func svgDigest() {
        let output = write(DrawingFixtures.assemblySheet(), title: "Assembly")
        #expect(output.data == write(DrawingFixtures.assemblySheet(), title: "Assembly").data)
        let digest = SHA256.hash(output.data)
            .map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
        #expect(digest == "7e03099e5e85c6b2d79373077aeffb7a6ff2fc4c662540fb672f1a8932c4668e")
    }
}

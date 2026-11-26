import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing
@testable import CreatorGraph

@Suite struct PDFWriterTests {
    private func write(_ pages: [SheetPicture], title: String = "Test") -> PDFOutput { PDFWriter.write(pages, title: title) }

    private func contentText(_ output: PDFOutput) -> String { pdfText(output.data) }

    @Test func theStructureIsValid() throws {
        let output = write([DrawingFixtures.a4Sheet(), DrawingFixtures.a4Sheet()])
        let reader = try PDFStructureReader(data: output.data)
        #expect(reader.objectCount == 4 + 2 * 2)
        #expect(reader.size == 9)
        #expect(reader.root == 1)
        #expect(reader.pages.count == 2)
        #expect(reader.xrefBytes.count == 9 * 20)
        #expect(!reader.xrefBytes.contains(13))
        #expect(Array(reader.xrefBytes.prefix(20)) == Array("0000000000 65535 f \n".utf8))
        for index in 0..<9 {
            let entry = Array(reader.xrefBytes[index * 20..<(index + 1) * 20])
            #expect(entry[18] == 0x20 && entry[19] == 0x0A)
        }
    }

    @Test func pagesAreTrueSize() throws {
        var a3 = SheetPicture(size: Vector2(420, 297))
        a3.strokes = []
        let output = write([DrawingFixtures.a4Sheet(), a3])
        let reader = try PDFStructureReader(data: output.data)
        #expect(reader.pages[0].mediaBox == [0, 0, 595.2756, 841.8898])
        #expect(reader.pages[1].mediaBox == [0, 0, 1190.5512, 841.8898])
    }

    @Test func aHalfScaleViewMeasuresHalfOnPaper() throws {
        var picture = SheetPicture(size: Vector2(210, 297))
        let line = SheetSegment.line(Vector2(0, 0), Vector2(100, 0)).transformed(scale: 0.5, offset: Vector2(10, 10))
        picture.strokes = [SheetStroke(segments: [line], width: 0.5, layer: .visible)]
        let reader = try PDFStructureReader(data: write([picture]).data)
        let operators = reader.pages[0].operators
        let cm = try #require(operators.first { $0.name == "cm" })
        let scale = try #require(Double(cm.operands[0]))
        let start = try #require(operators.first { $0.name == "m" })
        let end = try #require(operators.first { $0.name == "l" })
        let x0 = try #require(Double(start.operands[0])) * scale
        let x1 = try #require(Double(end.operands[0])) * scale
        #expect(abs((x1 - x0) - 141.7323) < 0.001)
        #expect(operators.first?.name == "cm")
        #expect(cm.operands == ["2.834645669", "0", "0", "2.834645669", "0", "0"])
    }

    @Test func lineWidthsAndDashesAreISO() throws {
        let reader = try PDFStructureReader(data: write([DrawingFixtures.a4Sheet()]).data)
        let operators = reader.pages[0].operators
        #expect(operators.contains(PDFOperator(name: "w", operands: ["0.5"])))
        #expect(operators.contains(PDFOperator(name: "w", operands: ["0.25"])))
        #expect(operators.contains(PDFOperator(name: "d", operands: ["[3", "1.5]", "0"])))
        #expect(operators.contains(PDFOperator(name: "J", operands: ["0"])))
        #expect(operators.contains(PDFOperator(name: "j", operands: ["1"])))
    }

    @Test func arcsAreCubics() throws {
        var picture = SheetPicture(size: Vector2(210, 297))
        picture.strokes = [
            SheetStroke(
                segments: [.arc(center: Vector2(50, 50), radius: 10, start: 0, sweep: 2 * .pi)], width: 0.5, layer: .visible),
        ]
        let reader = try PDFStructureReader(data: write([picture]).data)
        #expect(reader.pages[0].operators.filter { $0.name == "c" }.count == 4)
        #expect(reader.pages[0].operators.filter { $0.name == "m" }.count == 1)
    }

    @Test func textUsesHelveticaWinAnsi() throws {
        let output = write([DrawingFixtures.a4Sheet()])
        let text = contentText(output)
        #expect(text.contains("/BaseFont /Helvetica /Encoding /WinAnsiEncoding"))
        let reader = try PDFStructureReader(data: output.data)
        let shown = reader.pages[0].operators.filter { $0.name == "Tj" }.compactMap(\.operands.first)
        #expect(shown.contains { $0.hasPrefix("(\\33020 ") })
        #expect(reader.pages[0].operators.contains { $0.name == "Tf" && $0.operands.first == "/F1" })
    }

    @Test func escapes() throws {
        let reader = try PDFStructureReader(data: write([DrawingFixtures.a4Sheet()]).data)
        let shown = reader.pages[0].operators.filter { $0.name == "Tj" }.compactMap(\.operands.first)
        #expect(shown.contains("(a\\(b\\)c\\\\d)"))
    }

    @Test func replacedTextsAreReported() throws {
        let sheet = DrawingFixtures.a4Sheet()
        let output = write([sheet, sheet])
        #expect(output.replacedTexts == ["Ω-Bracket →"])
        let reader = try PDFStructureReader(data: output.data)
        let shown = reader.pages[0].operators.filter { $0.name == "Tj" }.compactMap(\.operands.first)
        #expect(shown.contains("(?-Bracket ?)"))
    }

    @Test func noDatesNoID() {
        let text = contentText(write([DrawingFixtures.a4Sheet()]))
        #expect(!text.contains("/CreationDate"))
        #expect(!text.contains("/ModDate"))
        #expect(!text.contains("/ID"))
        #expect(!text.contains("\r"))
    }

    @Test func numbersAreLocaleFree() {
        #expect(PDFNumber.format(-0.00001, decimals: 4) == "0")
        #expect(PDFNumber.format(1.5, decimals: 4) == "1.5")
        #expect(PDFNumber.format(-2.25, decimals: 4) == "-2.25")
        #expect(PDFNumber.format(1190.55118, decimals: 4) == "1190.5512")
        #expect(PDFNumber.format(3, decimals: 4) == "3")
        #expect(PDFNumber.format(0.5, decimals: 0) == "1")
    }

    @Test func theFixturesDigestIsPinned() {
        let digest = SHA256.hash(write([DrawingFixtures.a4Sheet()], title: "Fixture Ø").data)
            .map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
        #expect(digest == "abeb0954616adb795e7fe4749772aeac4853bb48ba4e9d2b0948ea1cab65228a")
    }

    // MARK: Annotations (DR-2 Task 6)

    private func annotatedPage(standard: DrawingStandard = .iso) -> SheetPicture {
        let style = DrawingStyle.of(standard)
        var picture = SheetPicture(size: Vector2(210, 297), standard: standard)
        picture.fills = [SheetFill(points: [Vector2(10, 10), Vector2(14, 11), Vector2(10, 12)])]
        picture.strokes = [
            SheetStroke(segments: [.line(Vector2(20, 20), Vector2(60, 20))], width: style.thin, pattern: .centre, layer: .center)
        ]
        picture.texts = [
            SheetText(
                run: DrawingText.layout("25 ±0.1", height: 3.5), original: "25 ±0.1", origin: Vector2(30, 40), height: 3.5,
                angle: .pi / 6),
            DrawingFixtures.text("-0.2", at: Vector2(30, 50), height: 3.5),
        ]
        return picture
    }

    @Test func fillsAreClosedAndFilled() throws {
        let reader = try PDFStructureReader(data: write([annotatedPage()]).data)
        let names = reader.pages[0].operators.map(\.name)
        let fillIndex = try #require(names.firstIndex(of: "f"))
        #expect(names[fillIndex - 1] == "h")
        #expect(Array(names[(fillIndex - 4)..<(fillIndex - 1)]) == ["m", "l", "l"])
    }

    @Test func rotatedTextUsesTm() throws {
        var picture = SheetPicture(size: Vector2(210, 297))
        picture.texts = [
            SheetText(run: DrawingText.layout("A", height: 3.5), original: "A", origin: Vector2(30, 40), height: 3.5, angle: .pi / 2)
        ]
        let reader = try PDFStructureReader(data: write([picture]).data)
        let tm = try #require(reader.pages[0].operators.first { $0.name == "Tm" })
        #expect(tm.operands == ["0", "1", "-1", "0", "30", "40"])
    }

    @Test func unrotatedTextKeepsTd() throws {
        let reader = try PDFStructureReader(data: write([DrawingFixtures.a4Sheet()]).data)
        #expect(reader.pages[0].operators.contains { $0.name == "Td" })
        #expect(!reader.pages[0].operators.contains { $0.name == "Tm" })
    }

    @Test func dashesFollowThePageStandard() throws {
        let asme = try PDFStructureReader(data: write([annotatedPage(standard: .asme)]).data)
        #expect(asme.pages[0].operators.contains(PDFOperator(name: "d", operands: ["[19", "1.5", "3", "1.5]", "0"])))
        let iso = try PDFStructureReader(data: write([annotatedPage(standard: .iso)]).data)
        #expect(iso.pages[0].operators.contains(PDFOperator(name: "d", operands: ["[6", "0.75", "0.25", "0.75]", "0"])))
    }

    @Test func theDR1DigestIsUnchanged() {
        theFixturesDigestIsPinned()
    }

    @Test func annotatedPageDigest() {
        let data = write([annotatedPage()], title: "Annotated").data
        let text = pdfText(data)
        #expect(text.contains("(-0.2)"))
        #expect(!text.contains("\\342\\210\\222"))
        #expect(data == write([annotatedPage()], title: "Annotated").data)
        let digest = SHA256.hash(data)
            .map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
        #expect(digest == "507244790ae669f26399498b99046bbbf361714154dbd7bab0d8ae76f2dda2ee")
    }

    @Test func hatchedPageDigest() {
        for standard in [DrawingStandard.iso, .asme] {
            let data = write([DrawingFixtures.hatchedSheet(standard: standard)], title: "Hatched").data
            #expect(data == write([DrawingFixtures.hatchedSheet(standard: standard)], title: "Hatched").data)
        }
        let data = write([DrawingFixtures.hatchedSheet()], title: "Hatched").data
        let digest = SHA256.hash(data)
            .map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
        #expect(digest == "8dbed6de4a6f62d8fa24220b2f76281465eb2daef29fc254861b87ec3a1a4c8e")
        #expect(pdfText(data).contains("(A)"))
    }

    private func hexDigest(_ data: Data) -> String {
        SHA256.hash(data).map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
    }

    @Test func symbolsPageDigest() {
        let data = write([DrawingFixtures.symbolsSheet()], title: "Symbols").data
        #expect(data == write([DrawingFixtures.symbolsSheet()], title: "Symbols").data)
        #expect(hexDigest(data) == "3f53241674cf53ed5154f56cbf8c452053959db29e448459a2039669a66a3d27")
        #expect(pdfText(data).contains("(1. Deburr.)"))
    }

    @Test func symbolsPageDigestASME() {
        let data = write([DrawingFixtures.symbolsSheet(standard: .asme)], title: "Symbols").data
        #expect(data == write([DrawingFixtures.symbolsSheet(standard: .asme)], title: "Symbols").data)
        #expect(hexDigest(data) == "31c43fff174f2ebefa56308740b3863d5f159582bc5c3810b266e803aa5fd652")
    }

    @Test func theSymbolsPageHasNoTextOutsideWinAnsi() throws {
        for standard in [DrawingStandard.iso, .asme] {
            let picture = DrawingFixtures.symbolsSheet(standard: standard)
            #expect(!picture.texts.isEmpty)
            #expect(picture.texts.allSatisfy { !$0.run.hasReplacements })
            // The header's binary comment aside, the writer escapes every byte outside ASCII.
            let data = write([picture], title: "Symbols").data
            let body = data.drop { $0 != 0x0A }.dropFirst().drop { $0 != 0x0A }
            #expect(body.allSatisfy { $0 < 0x80 })
        }
    }

    // MARK: Images and assemblies (DR-5 Task 6)

    @Test func assemblyPageDigest() {
        let data = write([DrawingFixtures.assemblySheet()], title: "Assembly").data
        #expect(data == write([DrawingFixtures.assemblySheet()], title: "Assembly").data)
        #expect(hexDigest(data) == "e995ea3695f352eb0385d74082e502c69e9cb8737977c4b4916ad0376f55098c")
    }

    @Test func imagesFollowThePages() throws {
        let output = write([DrawingFixtures.assemblySheet()], title: "Assembly")
        let reader = try PDFStructureReader(data: output.data)
        #expect(reader.pages.count == 1 && reader.objectCount == 4 + 2 + 1)
        let page = reader.objectText(5)
        #expect(page.contains("/XObject << /Im1 7 0 R >>"))
        let image = reader.objectText(7)
        #expect(image.contains("/Subtype /Image") && image.contains("/Width 4 /Height 3"))
        #expect(image.contains("/ColorSpace /DeviceGray /BitsPerComponent 8 /Length 12"))
        let body = try #require(image.range(of: "stream\n"))
        let bytes = Array(image[body.upperBound...].prefix(12).unicodeScalars.map { UInt8($0.value) })
        #expect(bytes == DrawingFixtures.logo.bytes)
        let content = reader.pages[0].operators
        #expect(content.first { $0.name == "Do" }?.operands == ["/Im1"])
        #expect(content.firstIndex { $0.name == "Do" } ?? 99 < content.firstIndex { $0.name == "S" } ?? 0, "under the ink")
    }

    @Test func aLogoOnTwoPagesIsOneObject() throws {
        let output = write([DrawingFixtures.assemblySheet(), DrawingFixtures.assemblySheet()], title: "Two")
        let reader = try PDFStructureReader(data: output.data)
        #expect(reader.pages.count == 2 && reader.objectCount == 4 + 4 + 1)
        #expect(reader.objectText(5).contains("/Im1 9 0 R") && reader.objectText(7).contains("/Im1 9 0 R"))
    }

    @Test func noImagesNoChange() throws {
        let data = write([DrawingFixtures.a4Sheet()], title: "Fixture Ø").data
        #expect(hexDigest(data) == "abeb0954616adb795e7fe4749772aeac4853bb48ba4e9d2b0948ea1cab65228a")
        #expect(!pdfText(data).contains("XObject"))
    }
}

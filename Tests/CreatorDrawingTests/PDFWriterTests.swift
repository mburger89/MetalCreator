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
}

import CreatorGeometry
import Foundation
import CreatorStyle
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Sheet lettering (plan R13): each glyph a `Text` at its Helvetica offset and on the text's baseline.
@MainActor
@Suite("Sheet text")
struct SheetTextViewTests {
    static func text(_ string: String, height: Double, at origin: Vector2) -> SheetText {
        SheetText(run: DrawingText.layout(string, height: height), original: string, origin: origin, height: height)
    }

    @Test func glyphsSitAtHelveticaAdvances() async throws {
        let height = 10.0, zoom = 3.0
        let text = Self.text("H1", height: height, at: Vector2(0, 40))
        let window = try await DrawingWindow.open(scaleFactor: 1) {
            SheetTextView(text: text, zoom: zoom, paperHeight: 50, color: ColorTheme.dracula.colors.drawingInk)
        }
        let glyphs = try window.window.elements(role: .staticText).sorted { $0.frame.origin.x < $1.frame.origin.x }
        try #require(glyphs.count == 2)
        let h = glyphs[0], one = glyphs[1]
        let em = height / 0.718 * zoom
        let offset = Double(one.frame.origin.x.value - h.frame.origin.x.value)
        #expect(abs(offset - 0.722 * em) < 0.1, "the second glyph starts one H advance in: \(offset) of \(em)")
        #expect(abs(Double(h.frame.origin.y.value) - Double(one.frame.origin.y.value)) < 0.01, "on one baseline")
    }

    #if canImport(MetalUITestingSnapshot)
    /// The lowest row of ink of an "H" is the baseline, at zoom 1 and zoom 3, and the PDF puts the same text's `Td` on the same line.
    @Test(arguments: [1.0, 3.0])
    func aCapitalHSitsOnTheBaseline(zoom: Double) async throws {
        let text = Self.text("H", height: 10, at: Vector2(20, 30))
        let colors = ColorTheme.dracula.colors
        let window = try await DrawingWindow.open(size: Size(width: Pixels(600), height: Pixels(500))) {
            colors.drawingPaper.color.overlay(alignment: .topLeading) {
                SheetTextView(text: text, zoom: zoom, paperHeight: 100, color: colors.drawingInk)
            }
        }
        let transform = SheetTransform(offset: Vector2(0, 100 * zoom), zoom: zoom)
        let image = try PixelImage(window: window.window)
        var lowest: Int?
        let x0 = Int(20 * zoom * 2), x1 = Int(30 * zoom * 2)
        for y in 0..<image.height {
            for x in x0..<x1 where image.luminance(x, y) < 128 { lowest = y }
        }
        let bottom = Double(try #require(lowest) + 1) / 2
        let baseline = transform.screenPoint(Vector2(20, 30)).y
        #expect(abs(bottom - baseline) <= 1, "ink ends at \(bottom), the baseline is \(baseline)")

        var picture = SheetPicture(size: Vector2(210, 100))
        picture.texts = [text]
        let reader = try PDFStructureReader(data: PDFWriter.write([picture], title: "H").data)
        let td = try #require(reader.pages[0].operators.first { $0.name == "Td" })
        let pdfY = try #require(Double(td.operands[1]))
        let mapped = transform.screenPoint(Vector2(20, pdfY)).y
        #expect(abs(mapped - baseline) <= 1, "the PDF's baseline lands at \(mapped)")
        #expect(abs(bottom - mapped) <= 1)
    }
    #endif
}

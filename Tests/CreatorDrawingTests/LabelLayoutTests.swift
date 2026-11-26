import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing

@Suite("Label layout")
struct LabelLayoutTests {
    private let style = AnnotationStyle.of(.iso)
    private let h = 2.5

    @Test func widthIsHelveticas() {
        let placed = LabelLayout.place(LayoutSupport.label("25"), height: h, center: .zero, angle: 0, style: style)
        #expect(placed.width == DrawingText.layout("25", height: h).width)
        #expect(placed.texts.count == 1 && placed.texts[0].run == DrawingText.layout("25", height: h))
        #expect(placed.box == nil)
    }

    @Test func symbolsAdvance1_6h() {
        let label = DimensionLabel(lines: [[.text("Ø6 "), .symbol(.depth), .text("10")]])
        let placed = LabelLayout.place(label, height: h, center: .zero, angle: 0, style: style)
        let expected = LayoutSupport.width("Ø6 ") + 1.6 * h + LayoutSupport.width("10")
        #expect(LayoutSupport.close(placed.width, expected))
        #expect(placed.texts.count == 2)
        let first = placed.texts[0], second = placed.texts[1]
        let gap = second.origin.x - (first.origin.x + first.run.width)
        #expect(LayoutSupport.close(gap, 1.6 * h))
        #expect(placed.segments.count == 3)
    }

    @Test func aStackFollowsTheValue() {
        var label = LayoutSupport.label("25")
        label.stack = StackedText(upper: "+0.1", lower: "-0.2")
        let placed = LabelLayout.place(label, height: h, center: .zero, angle: 0, style: style)
        #expect(placed.texts.count == 3)
        let main = placed.texts[0], upper = placed.texts[1], lower = placed.texts[2]
        #expect(upper.origin.x > main.origin.x + main.run.width)
        #expect(upper.origin.x == lower.origin.x)
        #expect(LayoutSupport.close(upper.height, style.toleranceScale * h))
        #expect(upper.origin.y > lower.origin.y)
        // The stack is centred on the main text's middle.
        let middle = main.origin.y + h / 2
        #expect(upper.origin.y > middle && lower.origin.y < middle)
        #expect(placed.width > main.run.width + upper.run.width * 0.9)
    }

    @Test func rotationKeepsTheCentre() {
        let centre = Vector2(50, 40)
        let flat = LabelLayout.place(LayoutSupport.label("40"), height: h, center: centre, angle: 0, style: style)
        let turned = LabelLayout.place(LayoutSupport.label("40"), height: h, center: centre, angle: .pi / 2, style: style)
        func middle(_ text: PlacedText) -> Vector2 {
            let u = Vector2(cos(text.angle), sin(text.angle)), up = Vector2(-u.y, u.x)
            return text.origin + u * (text.run.width / 2) + up * (text.height / 2)
        }
        #expect(LayoutSupport.close(middle(flat.texts[0]), centre))
        #expect(LayoutSupport.close(middle(turned.texts[0]), centre))
        #expect(turned.texts[0].angle == .pi / 2)
    }

    @Test func basicBoxPadsOneMillimetre() {
        var label = LayoutSupport.label("25")
        label.isBoxed = true
        let placed = LabelLayout.place(label, height: h, center: .zero, angle: 0, style: style)
        let box = try? #require(placed.box)
        let xs = (box ?? []).map(\.x), ys = (box ?? []).map(\.y)
        let w = LayoutSupport.width("25")
        #expect(LayoutSupport.close((xs.max() ?? 0) - (xs.min() ?? 0), w + 2))
        #expect(LayoutSupport.close((ys.max() ?? 0) - (ys.min() ?? 0), h + 2))
        #expect(LayoutSupport.close(placed.width, w + 2))
    }

    @Test func typedTextCarriesTheWholeLabelAsOriginal() {
        var label = DimensionLabel(lines: [[.text("2× Ø6")]], trailing: "TYP→", hasTypedText: true)
        label.isBoxed = false
        let placed = LabelLayout.place(label, height: h, center: .zero, angle: 0, style: style)
        #expect(placed.texts.count == 2)
        #expect(placed.texts.allSatisfy { $0.original == label.plainText })
        #expect(label.plainText == "2× Ø6 TYP→")
        let asSheet = placed.texts.map {
            SheetText(run: $0.run, original: $0.original, origin: $0.origin, height: $0.height)
        }
        #expect(ReplacedTexts.collect(asSheet) == ["2× Ø6 TYP→"])
        let plain = DimensionLabel(lines: [[.text("2× Ø6")]], trailing: "TYP")
        let pieces = LabelLayout.place(plain, height: h, center: .zero, angle: 0, style: style)
        #expect(pieces.texts.map(\.original) == ["2× Ø6", "TYP"])
    }
}

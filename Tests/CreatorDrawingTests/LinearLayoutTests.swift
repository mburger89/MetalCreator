import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite("Linear dimension layout")
struct LinearLayoutTests {
    private let h = LayoutSupport.h
    private let x = Vector2(1, 0)
    private let y = Vector2(0, 1)

    private func horizontal(
        length: Double = 40, offset: Double = 10, label: String = "40", textShift: Double? = nil,
        standard: DrawingStandard = .iso
    ) -> AnnotationDrawing {
        LayoutSupport.linear(
            .zero, Vector2(length, 0), direction: x, kind: .linear(.horizontal), labels: [LayoutSupport.label(label)],
            offset: offset, textShift: textShift, standard: standard)
    }

    @Test func isoTextSitsAboveParallel() {
        let drawing = horizontal()
        let w = LayoutSupport.width("40")
        #expect(drawing.texts.count == 1)
        let text = drawing.texts[0]
        #expect(text.angle == 0)
        #expect(LayoutSupport.close(text.origin, Vector2(20 - w / 2, 11)))
        #expect(LayoutSupport.hasLine(drawing, Vector2(0, 10), Vector2(40, 10)))
        #expect(LayoutSupport.close(drawing.textCenter ?? .zero, Vector2(20, 11 + h / 2)))
    }

    @Test func isoVerticalTextReadsFromTheRight() {
        let drawing = LayoutSupport.linear(
            .zero, Vector2(0, 40), direction: y, kind: .linear(.vertical), labels: [LayoutSupport.label("40")], offset: 10)
        #expect(drawing.texts[0].angle == .pi / 2)
        // The line is at x = -10 (n is d turned +90 degrees); the baseline lies 1 mm toward the text's up, which is -x.
        #expect(LayoutSupport.hasLine(drawing, Vector2(-10, 0), Vector2(-10, 40)))
    }

    @Test func asmeTextIsHorizontalInABreak() {
        let drawing = horizontal(standard: .asme)
        let w = LayoutSupport.width("40")
        let text = drawing.texts[0]
        #expect(text.angle == 0)
        #expect(LayoutSupport.close(text.origin, Vector2(20 - w / 2, 10 - h / 2)))
        let style = AnnotationStyle.of(.asme)
        let left = 20 - w / 2 - style.textGap, right = 20 + w / 2 + style.textGap
        #expect(LayoutSupport.hasLine(drawing, Vector2(0, 10), Vector2(left, 10)))
        #expect(LayoutSupport.hasLine(drawing, Vector2(right, 10), Vector2(40, 10)))
        #expect(LayoutSupport.close(right - left, w + 3))
    }

    @Test func extensionLinesGapAndOvershoot() {
        let iso = horizontal()
        #expect(LayoutSupport.hasLine(iso, Vector2(0, 0), Vector2(0, 12)))
        #expect(LayoutSupport.hasLine(iso, Vector2(40, 0), Vector2(40, 12)))
        let asme = horizontal(standard: .asme)
        #expect(LayoutSupport.hasLine(asme, Vector2(0, 1.5), Vector2(0, 13)))
        #expect(LayoutSupport.hasLine(asme, Vector2(40, 1.5), Vector2(40, 13)))
    }

    @Test func aShortDimensionFlipsItsArrows() {
        let drawing = horizontal(length: 2, label: "2")
        #expect(drawing.fills.count == 2)
        let tips = drawing.fills.map { $0[0] }
        #expect(tips.contains { LayoutSupport.close($0, Vector2(0, 10)) })
        #expect(tips.contains { LayoutSupport.close($0, Vector2(2, 10)) })
        // The head at 0 sits outside, its base 2.5 mm out, and a tail of 2.5 mm runs on from there.
        let head = drawing.fills.first { LayoutSupport.close($0[0], Vector2(0, 10)) } ?? []
        let base = Vector2((head[1].x + head[2].x) / 2, (head[1].y + head[2].y) / 2)
        #expect(LayoutSupport.close(base, Vector2(-2.5, 10)))
        #expect(LayoutSupport.hasLine(drawing, Vector2(-2.5, 10), Vector2(-5, 10)))
    }

    @Test(arguments: [DrawingStandard.iso, DrawingStandard.asme])
    func textOutsideClearsTheExtensionLines(standard: DrawingStandard) {
        let drawing = horizontal(length: 8, label: "1234567890", standard: standard)
        let style = AnnotationStyle.of(standard)
        let text = drawing.texts[0]
        #expect(text.origin.x >= 8 + style.textGap + style.arrowLength - 1e-9)
        #expect(drawing.textCenter.map { $0.x > 8 } == true)
    }

    @Test func aTextShiftMovesTheTextAndExtendsTheLine() {
        let drawing = horizontal(textShift: 35)
        let w = LayoutSupport.width("40")
        #expect(LayoutSupport.close(drawing.texts[0].origin.x, 55 - w / 2))
        let reach = LayoutSupport.lines(drawing).filter { $0.0.y == 10 && $0.1.y == 10 }.flatMap { [$0.0.x, $0.1.x] }.max() ?? 0
        #expect(reach >= 55 + w / 2 - 1e-9)
    }

    @Test func baselineStacks() {
        let points = [Vector2(0, 0), Vector2(10, 0), Vector2(25, 0)]
        let drawing = LayoutSupport.linear(
            points[0], points[2], direction: x, kind: .baseline(.horizontal),
            labels: [LayoutSupport.label("10"), LayoutSupport.label("25")], offset: 10, points: points)
        #expect(drawing.texts.count == 2)
        #expect(LayoutSupport.close(drawing.texts[0].origin.y, 11))
        #expect(LayoutSupport.close(drawing.texts[1].origin.y, 19))
        #expect(LayoutSupport.hasLine(drawing, Vector2(0, 10), Vector2(10, 10)))
        #expect(LayoutSupport.hasLine(drawing, Vector2(0, 18), Vector2(25, 18)))
        // The first point's extension line reaches the farthest line.
        #expect(LayoutSupport.hasLine(drawing, Vector2(0, 0), Vector2(0, 20)))
    }

    @Test func chainSharesOneLine() {
        let points = [Vector2(0, 0), Vector2(10, 0), Vector2(25, 0)]
        let drawing = LayoutSupport.linear(
            points[0], points[2], direction: x, kind: .chain(.horizontal),
            labels: [LayoutSupport.label("10"), LayoutSupport.label("15")], offset: 10, points: points)
        #expect(drawing.texts.map(\.origin.y).allSatisfy { LayoutSupport.close($0, 11) })
        #expect(LayoutSupport.hasLine(drawing, Vector2(0, 10), Vector2(10, 10)))
        #expect(LayoutSupport.hasLine(drawing, Vector2(10, 10), Vector2(25, 10)))
        #expect(drawing.fills.count == 4)
    }

    @Test func ordinateLeadersEndOnTheLine() {
        let drawing = SheetDimensionLayout.draw(
            .ordinate(origin: .zero, points: [Vector2(10, 0), Vector2(25, 0)], direction: x), kind: .ordinate(.horizontal),
            labels: [LayoutSupport.label("0"), LayoutSupport.label("10"), LayoutSupport.label("25")],
            placement: DimensionPlacement(offset: 20, angle: 0), mapping: LayoutSupport.identity, standard: .iso, height: h)
        #expect(drawing.texts.map(\.run.shown) == ["0", "10", "25"])
        for x in [0.0, 10, 25] { #expect(LayoutSupport.hasLine(drawing, Vector2(x, 0), Vector2(x, 20))) }
        // The text sits beyond the line, along the leader.
        #expect(drawing.texts.allSatisfy { $0.angle == .pi / 2 })
        #expect(drawing.texts[0].origin.y >= 20)
    }

    @Test func arrowheadsAreTriangles() {
        let drawing = horizontal()
        #expect(drawing.fills.count == 2)
        for fill in drawing.fills {
            #expect(fill.count == 3)
            let base = Vector2((fill[1].x + fill[2].x) / 2, (fill[1].y + fill[2].y) / 2)
            #expect(LayoutSupport.close((base - fill[0]).length, 2.5))
            #expect(LayoutSupport.close((fill[1] - fill[2]).length, 2.5 / 3))
        }
        let asme = horizontal(standard: .asme)
        #expect(LayoutSupport.close((asme.fills[0][1] - asme.fills[0][2]).length, 1))
    }

    @Test func theFrameHoldsEverything() {
        let drawing = horizontal()
        #expect(drawing.frame.min.x <= 0 && drawing.frame.max.x >= 40)
        #expect(drawing.frame.max.y >= 12)
        #expect(drawing.boxes.isEmpty)
    }

    @Test func aMappingMovesTheFigure() {
        let drawing = SheetDimensionLayout.draw(
            .linear(points: [.zero, Vector2(40, 0)], direction: x), kind: .linear(.horizontal),
            labels: [LayoutSupport.label("40")], placement: DimensionPlacement(offset: 10, angle: 0),
            mapping: ViewMapping(scale: 0.5, offset: Vector2(100, 50)), standard: .iso, height: h)
        #expect(LayoutSupport.hasLine(drawing, Vector2(100, 60), Vector2(120, 60)))
    }
}

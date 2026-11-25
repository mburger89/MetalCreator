import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite("Drawing symbols")
struct DrawingSymbolsTests {
    private let centre = Vector2(100, 50)
    private let h = 2.5

    private func circles(_ strokes: [SheetStroke]) -> [(Vector2, Double)] {
        strokes.compactMap { stroke in
            if case let .arc(c, r, _, _) = stroke.segments[0] { return (c, r) }
            return nil
        }
    }

    @Test func firstAngleHasTheCirclesOnTheRight() {
        let strokes = DrawingSymbols.projectionSymbol(firstAngle: true, center: centre, h: h)
        #expect(circles(strokes).allSatisfy { $0.0.x > centre.x })
        guard case let .polyline(cone) = strokes[0].segments[0] else {
            Issue.record("no cone")
            return
        }
        #expect(cone.allSatisfy { $0.x < centre.x })
        #expect(cone[0].x < cone[1].x)  // big end at the left
    }

    @Test func thirdAngleHasTheCirclesOnTheLeft() {
        let strokes = DrawingSymbols.projectionSymbol(firstAngle: false, center: centre, h: h)
        #expect(circles(strokes).allSatisfy { $0.0.x < centre.x })
        guard case let .polyline(cone) = strokes[0].segments[0] else {
            Issue.record("no cone")
            return
        }
        #expect(cone.allSatisfy { $0.x > centre.x })
        #expect(cone[0].x < cone[1].x)  // big end toward the circles, on the left
    }

    @Test func proportionsFollowH() throws {
        for first in [true, false] {
            let strokes = DrawingSymbols.projectionSymbol(firstAngle: first, center: centre, h: h, thin: 0.25)
            #expect(strokes.allSatisfy { $0.width == 0.25 })
            #expect(Set(circles(strokes).map(\.1)) == [h, h / 2])
            guard case let .polyline(cone) = strokes[0].segments[0] else {
            Issue.record("no cone")
            return
        }
            let heights = Set([abs(cone[0].y - cone[3].y), abs(cone[1].y - cone[2].y)])
            #expect(heights == [2 * h, h])
            let bounds = strokes.map(\.bounds).dropFirst().reduce(strokes[0].bounds) { $0.union($1) }
            let size = DrawingSymbols.projectionSymbolSize(h: h)
            #expect(size == Vector2(15, 5))
            #expect(abs(bounds.width - size.x) < 1e-9 && abs(bounds.height - size.y) < 1e-9)
            #expect(abs(bounds.center.x - centre.x) < 1e-9 && abs(bounds.center.y - centre.y) < 1e-9)
        }
    }

    @Test func theSymbolLiesInsideItsField() throws {
        for standard in [DrawingStandard.iso, .asme] {
            for size in [SheetSize.a3, .a0] {
                let sheet = DrawingSheet(name: "S", size: size)
                let picture = TitleBlockLayout.picture(
                    sheet: sheet, settings: DrawingSettings(standard: standard), facts: TitleBlockFacts(), sheetIndex: 0,
                    sheetCount: 1)
                let origin = TitleBlockLayout.origin(for: sheet, standard: standard)
                let field = Rect2D(
                    min: Vector2(origin.x + 162, origin.y + 10), max: Vector2(origin.x + 180, origin.y + 20))
                let inner = Rect2D(
                    min: Vector2(field.min.x + 1, field.min.y + 1), max: Vector2(field.max.x - 1, field.max.y - 1))
                let thin = DrawingStyle.of(standard).thin
                let symbol = picture.strokes.filter { $0.width == thin }
                #expect(symbol.count == 4)
                for stroke in symbol {
                    let b = stroke.bounds
                    #expect(b.min.x >= inner.min.x - 1e-9 && b.max.x <= inner.max.x + 1e-9)
                    #expect(b.min.y >= inner.min.y - 1e-9 && b.max.y <= inner.max.y + 1e-9)
                }
            }
        }
    }
}

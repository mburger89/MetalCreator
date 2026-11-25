import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Centre marks")
struct CentreMarkTests {
    private typealias Fixtures = AnnotationFixtures

    private func circle(
        _ radius: Double, at center: Vector2 = Vector2(20, 10), edge: Int? = 0, visibility: LineVisibility = .visible,
        sweep: Double = 2 * .pi
    ) -> ProjectedLine {
        Fixtures.line(.arc(center: center, radius: radius, start: 0, sweep: sweep), edge: edge, visibility: visibility)
    }

    private func marks(_ lines: [ProjectedLine], shows: Bool = true) -> [SheetStroke] {
        let view = Fixtures.makeView(showsCentreMarks: shows)
        let picture = Fixtures.compose(view, [], content: ViewContent(projection: Projection2D(lines: lines)))
        return picture.strokes.filter { $0.layer == .center }
    }

    private func reach(_ stroke: SheetStroke) -> Double {
        guard case let .line(a, b)? = stroke.segments.first else { return 0 }
        return (b - a).length / 2
    }

    @Test func aFaceOnCircleGetsAMark() {
        let strokes = marks([circle(5)])
        #expect(strokes.count == 2)
        #expect(strokes.allSatisfy { $0.pattern == .centre && $0.annotation == nil && $0.source == nil })
        #expect(strokes.allSatisfy { abs(reach($0) - 7) < 1e-9 })
    }

    @Test func concentricCirclesShareOne() {
        let strokes = marks([circle(5), circle(8, edge: 1), circle(3, edge: 2)])
        #expect(strokes.count == 2)
        #expect(strokes.allSatisfy { abs(reach($0) - 10) < 1e-9 })
    }

    @Test func separateCentresGetOneEach() {
        #expect(marks([circle(5), circle(5, at: Vector2(60, 10), edge: 1)]).count == 4)
    }

    @Test func aSmallCircleGetsASolidCross() {
        let strokes = marks([circle(1)])
        #expect(strokes.count == 2 && strokes.allSatisfy { $0.pattern == .solid })
        #expect(strokes.allSatisfy { abs(reach($0) - 3) < 1e-9 })
    }

    @Test func arcsAndHiddenCirclesGetNone() {
        #expect(marks([circle(5, sweep: .pi)]).isEmpty)
        #expect(marks([circle(5, visibility: .hidden)]).isEmpty)
        #expect(marks([circle(5, edge: nil)]).isEmpty)
    }

    @Test func theViewFlagTurnsThemOff() {
        #expect(marks([circle(5)], shows: false).isEmpty)
    }

    @Test func theMarkSitsOnTheCircleCentreOnTheSheet() throws {
        let strokes = marks([circle(5)])
        // The view's bounds centre (20, 10) maps to the view centre (150, 150).
        guard case let .line(a, b)? = strokes.first?.segments.first else { return }
        #expect(LayoutSupport.close((a + b) * 0.5, Vector2(150, 150)))
    }
}

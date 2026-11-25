import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite("Sheet hit test")
struct SheetHitTestTests {
    private let a = ViewID()
    private let b = ViewID()

    private var picture: SheetPicture {
        SheetPicture(
            size: Vector2(420, 297),
            strokes: [
                SheetStroke(segments: [.line(Vector2(0, 0), Vector2(10, 0))], width: 0.5, layer: .visible, view: a),
                SheetStroke(
                    segments: [.arc(center: Vector2(50, 50), radius: 10, start: 0, sweep: 2 * .pi)], width: 0.5,
                    layer: .visible, view: b),
            ],
            viewFrames: [
                a: Rect2D(min: Vector2(0, 0), max: Vector2(50, 50)), b: Rect2D(min: Vector2(40, 40), max: Vector2(90, 90)),
            ])
    }

    @Test func theTopmostViewWins() {
        #expect(SheetHitTest.view(at: Vector2(45, 45), in: picture, order: [a, b]) == b)
        #expect(SheetHitTest.view(at: Vector2(45, 45), in: picture, order: [b, a]) == a)
        #expect(SheetHitTest.view(at: Vector2(51.5, 10), in: picture, order: [a, b]) == a)
    }

    @Test func aLineWithinToleranceIsFound() {
        #expect(SheetHitTest.line(near: Vector2(5, 1), in: picture, view: a, tolerance: 2) == 0)
        #expect(SheetHitTest.line(near: Vector2(60.5, 50), in: picture, view: b, tolerance: 1) == 1)
    }

    @Test func nothingNearIsNil() {
        #expect(SheetHitTest.line(near: Vector2(5, 20), in: picture, view: a, tolerance: 2) == nil)
        #expect(SheetHitTest.view(at: Vector2(300, 200), in: picture, order: [a, b]) == nil)
    }
}

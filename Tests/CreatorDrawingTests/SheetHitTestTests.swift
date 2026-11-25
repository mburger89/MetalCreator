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

    @Test func lineHitsSkipAnnotationAndCentreStrokes() {
        let annotated = AnnotationID()
        let drawn = SheetPicture(
            size: Vector2(100, 100),
            strokes: [
                SheetStroke(
                    segments: [.line(Vector2(0, 0), Vector2(10, 0))], width: 0.5, layer: .dimension, view: a,
                    annotation: annotated),
                SheetStroke(segments: [.line(Vector2(0, 1), Vector2(10, 1))], width: 0.25, layer: .center, view: a),
                SheetStroke(segments: [.line(Vector2(0, 4), Vector2(10, 4))], width: 0.5, layer: .visible, view: a),
            ])
        #expect(SheetHitTest.line(near: Vector2(5, 0.5), in: drawn, view: a, tolerance: 5) == 2)
        #expect(SheetHitTest.line(near: Vector2(5, 0.5), in: drawn, view: a, tolerance: 2) == nil)
    }

    @Test func theTopmostAnnotationWins() {
        let first = AnnotationID()
        let second = AnnotationID()
        let missing = AnnotationID()
        func report(_ rect: Rect2D) -> AnnotationReport { AnnotationReport(status: .held, frame: rect) }
        let drawn = SheetPicture(
            size: Vector2(100, 100),
            annotationReports: [
                first: report(Rect2D(min: Vector2(10, 10), max: Vector2(30, 20))),
                second: report(Rect2D(min: Vector2(20, 10), max: Vector2(40, 20))),
            ])
        let order = [first, second, missing]
        #expect(SheetHitTest.annotation(at: Vector2(25, 15), in: drawn, order: order) == second)
        #expect(SheetHitTest.annotation(at: Vector2(15, 15), in: drawn, order: order) == first)
        #expect(SheetHitTest.annotation(at: Vector2(25, 15), in: drawn, order: [second, first]) == first)
        // Grown by 1 mm on every side.
        #expect(SheetHitTest.annotation(at: Vector2(41, 15), in: drawn, order: order) == second)
        #expect(SheetHitTest.annotation(at: Vector2(41.5, 15), in: drawn, order: order) == nil)
        #expect(SheetHitTest.annotation(at: Vector2(0, 0), in: drawn, order: order) == nil)
    }
}

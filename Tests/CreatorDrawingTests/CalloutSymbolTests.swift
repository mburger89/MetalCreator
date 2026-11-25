import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite struct CalloutSymbolTests {
    let h = 2.5
    let origin = Vector2(10, 20)

    func point(_ x: Double, _ y: Double) -> Vector2 { Vector2(origin.x + x * h, origin.y + y * h) }

    @Test func depthStrokes() {
        #expect(
            DrawingSymbols.labelSymbol(.depth, origin: origin, h: h) == [
                .line(point(0.5, 1), point(0.5, 0)),
                .polyline([point(0.15, 0.35), point(0.5, 0), point(0.85, 0.35)]),
                .line(point(0, 0), point(1, 0)),
            ])
    }

    @Test func counterboreStrokes() {
        #expect(
            DrawingSymbols.labelSymbol(.counterbore, origin: origin, h: h) == [
                .polyline([point(0, 0.6), point(0, 0), point(1, 0), point(1, 0.6)])
            ])
    }

    @Test func countersinkStrokes() {
        #expect(
            DrawingSymbols.labelSymbol(.countersink, origin: origin, h: h) == [
                .polyline([point(0, 0.6), point(0.5, 0), point(1, 0.6)])
            ])
    }

    @Test func advanceIsOnePointSixH() {
        #expect(DrawingSymbols.labelSymbolAdvance(h: 2.5) == 4.0)
        #expect(DrawingSymbols.labelSymbolAdvance(h: 3.5) == 1.6 * 3.5)
    }
}

import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite struct DatumSymbolTests {
    let h = 2.5

    @Test func theTriangleSitsOnTheLine() {
        let foot = Vector2(5, 6), along = Vector2(1, 0), n = Vector2(0, 1)
        let fill = DrawingSymbols.datumTriangle(foot: foot, along: along, toward: n, h: h)
        #expect(fill.count == 3)
        #expect(fill[0] == Vector2(5 - 0.6 * h, 6) && fill[1] == Vector2(5 + 0.6 * h, 6))
        #expect(fill[2] == Vector2(5, 6 + 1.2 * h * DrawingSymbols.sixty))
        // Equilateral: all three sides are 1.2h.
        func length(_ a: Vector2, _ b: Vector2) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }
        #expect(abs(length(fill[0], fill[2]) - 1.2 * h) <= 1e-12)
    }

    @Test func theSquareIsTwoH() {
        let square = DrawingSymbols.datumSquare(center: Vector2(10, 10), h: h)
        #expect(square.count == 5 && square.first == square.last)
        #expect(square[0] == Vector2(10 - h, 10 - h) && square[2] == Vector2(10 + h, 10 + h))
    }
}

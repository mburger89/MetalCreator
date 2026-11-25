import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing

@Suite("Cubics")
struct CubicsTests {
    private func near(_ a: Vector2, _ b: Vector2, _ tolerance: Double) -> Bool { (a - b).length <= tolerance }

    @Test func aQuarterArcIsOnePiece() throws {
        let pieces = SheetSegment.arc(center: Vector2(1, 2), radius: 3, start: 0, sweep: .pi / 2).cubics()
        let piece = try #require(pieces.first)
        #expect(pieces.count == 1)
        let k = 4.0 / 3.0 * tan(.pi / 8) * 3
        #expect(near(piece.start, Vector2(4, 2), 1e-12) && near(piece.end, Vector2(1, 5), 1e-12))
        #expect(near(piece.control1, Vector2(4, 2 + k), 1e-12))
        #expect(near(piece.control2, Vector2(1 + k, 5), 1e-12))
    }

    @Test func aFullCircleIsFourPieces() {
        #expect(SheetSegment.arc(center: .zero, radius: 1, start: 0, sweep: 2 * .pi).cubics().count == 4)
        #expect(SheetSegment.arc(center: .zero, radius: 1, start: 0, sweep: -2 * .pi).cubics().count == 4)
        #expect(SheetSegment.arc(center: .zero, radius: 1, start: 0, sweep: 1).cubics().count == 1)
        #expect(SheetSegment.line(.zero, Vector2(1, 1)).cubics().isEmpty)
    }

    @Test func piecesStayOnTheCircle() {
        let radius = 7.0
        let centre = Vector2(3, -2)
        for sweep in [2 * Double.pi, -2.5, 4.0] {
            for piece in SheetSegment.arc(center: centre, radius: radius, start: 0.3, sweep: sweep).cubics() {
                let mid = (piece.start + piece.control1 * 3 + piece.control2 * 3 + piece.end) * 0.125
                #expect(abs((mid - centre).length - radius) < 3e-4 * radius)
            }
        }
    }

    @Test func anEllipseIsAnAffineCircle() {
        let axis = Vector2(0.6, 0.8)
        let pieces = SheetSegment.ellipse(
            center: Vector2(5, 5), majorAxis: axis, majorRadius: 4, minorRadius: 2, start: 0, sweep: 2 * .pi
        ).cubics()
        #expect(pieces.count == 4)
        let minor = Vector2(-0.8, 0.6)
        for piece in pieces {
            for point in [piece.start, piece.end, (piece.start + piece.control1 * 3 + piece.control2 * 3 + piece.end) * 0.125] {
                let d = point - Vector2(5, 5)
                let u = d.x * axis.x + d.y * axis.y, v = d.x * minor.x + d.y * minor.y
                #expect(abs((u / 4) * (u / 4) + (v / 2) * (v / 2) - 1) < 1e-3)
            }
        }
        #expect(near(pieces[0].start, Vector2(5, 5) + axis * 4, 1e-12))
    }
}

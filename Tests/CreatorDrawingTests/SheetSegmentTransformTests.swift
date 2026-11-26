import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing

@Suite("Sheet segment transforms")
struct SheetSegmentTransformTests {
    private func points(of segment: SheetSegment, count: Int = 5) -> [Vector2] {
        switch segment {
        case let .ellipse(center, axis, major, minor, start, sweep):
            let length = axis.length
            let u = Vector2(axis.x / length, axis.y / length)
            return (0..<count).map { k in
                SheetSegment.point(center: center, u: u, major: major, minor: minor, at: start + sweep * Double(k) / Double(count - 1))
            }
        case let .arc(center, radius, start, sweep):
            return (0..<count).map { k in
                let t = start + sweep * Double(k) / Double(count - 1)
                return Vector2(center.x + radius * cos(t), center.y + radius * sin(t))
            }
        default: return []
        }
    }

    private func expectNear(_ a: [Vector2], _ b: [Vector2]) {
        #expect(a.count == b.count)
        for (p, q) in zip(a, b) { #expect(abs(p.x - q.x) < 1e-9 && abs(p.y - q.y) < 1e-9, "\(p) vs \(q)") }
    }

    @Test func anEllipticArcMirroredInXGivesTheMirroredPoints() {
        let ellipse = SheetSegment.ellipse(
            center: Vector2(3, 2), majorAxis: Vector2(0.6, 0.8), majorRadius: 5, minorRadius: 2, start: 0.4, sweep: 2.1)
        let mirrored = ellipse.transformed(scaleX: -1, scaleY: 1, offset: .zero)
        expectNear(points(of: mirrored), points(of: ellipse).map { Vector2(-$0.x, $0.y) })
    }

    @Test func aMirrorInYAndAMoveGiveTheMovedMirroredPoints() {
        let ellipse = SheetSegment.ellipse(
            center: Vector2(-1, 4), majorAxis: Vector2(1, 0), majorRadius: 3, minorRadius: 1, start: -1, sweep: 4)
        let result = ellipse.transformed(scaleX: 1, scaleY: -1, offset: Vector2(10, 5))
        expectNear(points(of: result), points(of: ellipse).map { Vector2($0.x + 10, -$0.y + 5) })
    }

    @Test func aNonUniformScaleKeepsEveryPoint() {
        let ellipse = SheetSegment.ellipse(
            center: Vector2(1, 1), majorAxis: Vector2(0.6, 0.8), majorRadius: 4, minorRadius: 3, start: 0.2, sweep: 5)
        let result = ellipse.transformed(scaleX: 2, scaleY: 0.5, offset: Vector2(1, 2))
        expectNear(points(of: result), points(of: ellipse).map { Vector2($0.x * 2 + 1, $0.y * 0.5 + 2) })
    }

    @Test func aMirroredArcKeepsItsEnds() {
        let arc = SheetSegment.arc(center: Vector2(2, 1), radius: 3, start: 0.3, sweep: 1.5)
        let result = arc.transformed(scaleX: -1, scaleY: 1, offset: .zero)
        expectNear(points(of: result), points(of: arc).map { Vector2(-$0.x, $0.y) })
    }

    @Test func aPlainScaleStillGivesAnArc() {
        let arc = SheetSegment.arc(center: Vector2(2, 1), radius: 3, start: 0.3, sweep: 1.5)
        #expect(arc.transformed(scale: 2, offset: Vector2(1, 1)) == .arc(center: Vector2(5, 3), radius: 6, start: 0.3, sweep: 1.5))
    }
}

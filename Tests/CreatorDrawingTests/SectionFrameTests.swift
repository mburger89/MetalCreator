import Foundation
import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

struct SectionFrameTests {
    private let top = StandardOrientation.top.frame

    private func close(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length < 1e-12 }

    private func same(_ a: ProjectionFrame, _ b: ProjectionFrame) -> Bool {
        close(a.direction, b.direction) && close(a.up, b.up)
    }

    @Test(arguments: [DrawingStandard.iso, .asme])
    func aStraightSectionMatchesTheProjectedView(standard: DrawingStandard) {
        let origin = Vector2(3, 4)
        let cases: [(t: Vector2, drop: Vector2, offset: Vector2)] = [
            (Vector2(1, 0), Vector2(3, 50), Vector2(0, 50)),
            (Vector2(1, 0), Vector2(3, -50), Vector2(0, -50)),
            (Vector2(0, 1), Vector2(50, 4), Vector2(50, 0)),
            (Vector2(0, 1), Vector2(-50, 4), Vector2(-50, 0)),
        ]
        for item in cases {
            let v = SectionFrame.viewing(along: item.t, from: origin, drop: item.drop, standard: standard)
            let frame = SectionFrame.frame(parent: top, along: item.t, viewing: v)
            let expected = ProjectedViewRule.view(from: top, dropOffset: item.offset, standard: standard).frame
            #expect(same(frame, expected))
        }
    }

    @Test func aSlantedLineReadsHorizontally() {
        let angle = 30.0 * Double.pi / 180
        let t = Vector2(angle.cosForTest, angle.sinForTest)
        let v = Vector2(-t.y, t.x)
        let frame = SectionFrame.frame(parent: top, along: t, viewing: v)
        let line3 = top.right * t.x + top.up * t.y
        #expect(close(frame.right, line3))
    }

    @Test func aSteepLineReadsVertically() {
        let angle = 70.0 * Double.pi / 180
        let t = Vector2(angle.cosForTest, angle.sinForTest)
        let v = Vector2(-t.y, t.x)
        let frame = SectionFrame.frame(parent: top, along: t, viewing: v)
        let line3 = top.right * t.x + top.up * t.y
        #expect(close(frame.up, line3))
    }

    @Test func firstAngleLooksTowardTheDrop() {
        let v = SectionFrame.viewing(along: Vector2(1, 0), from: .zero, drop: Vector2(0, -5), standard: .iso)
        #expect(v == Vector2(0, -1))
    }

    @Test func thirdAngleLooksAway() {
        let v = SectionFrame.viewing(along: Vector2(1, 0), from: .zero, drop: Vector2(0, -5), standard: .asme)
        #expect(v == Vector2(0, 1))
    }

    @Test func alignmentByDirection() {
        #expect(SectionFrame.alignment(along: Vector2(1, 0)) == .vertical)
        #expect(SectionFrame.alignment(along: Vector2(0, -1)) == .horizontal)
        #expect(SectionFrame.alignment(along: Vector2(0.6, 0.8)) == nil)
    }

    @Test func framesAreUnitAndSquare() throws {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        for _ in 0..<500 {
            let a = next() * 2 * Double.pi
            let t = Vector2(a.cosForTest, a.sinForTest)
            let v = next() < 0.5 ? Vector2(-t.y, t.x) : Vector2(t.y, -t.x)
            let frame = SectionFrame.frame(parent: top, along: t, viewing: v)
            try frame.validate()
        }
    }
}

extension Double {
    fileprivate var cosForTest: Double { Foundation.cos(self) }
    fileprivate var sinForTest: Double { Foundation.sin(self) }
}

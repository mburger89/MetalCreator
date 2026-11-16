import CreatorGeometry
import Testing
@testable import CreatorPCB

struct OutlineDigestTests {
    /// FNV-1a 64 over each segment's kind byte and its numbers' bit patterns, little-endian.
    static func digest(_ segments: [Segment2D]) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func put(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        func feed(_ value: Double) {
            var bits = value.bitPattern
            for _ in 0..<8 {
                put(UInt8(bits & 0xFF))
                bits >>= 8
            }
        }
        for segment in segments {
            switch segment {
            case .line(let a, let b):
                put(0)
                [a.x, a.y, b.x, b.y].forEach(feed)
            case .arc(let c, let r, let s, let e):
                put(1)
                [c.x, c.y, r, s.radians, e.radians].forEach(feed)
            case .spline(let curve):
                put(2)
                curve.poles.forEach { feed($0.x); feed($0.y) }
                curve.knots.forEach(feed)
                curve.multiplicities.forEach { feed(Double($0)) }
            }
        }
        return hash
    }

    @Test func rectangleAndRoundedDigestsArePinned() throws {
        let rectangle = try OutlineChainer.chain(OutlineChainerTests.rectangle, tolerance: 0.01)
        #expect(Self.digest(rectangle.outer) == 0xFD20_CE3B_8D01_27A5)
        let items = OutlineChainerTests.rounded
        let rounded = try OutlineChainer.chain(items, tolerance: 0.01)
        #expect(Self.digest(rounded.outer) == 0x4449_377B_7AE6_30BC)
    }
}

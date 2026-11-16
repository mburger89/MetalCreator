import CreatorGeometry
import Testing
@testable import CreatorPCB

struct OutlineDigestTests {
    /// FNV-1a 64 over each segment's kind byte and its numbers as integers (nanometres, or 1e-9 rad for angles and knots), little-endian.
    static func digest(_ segments: [Segment2D]) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func put(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        func feed(_ value: Double, scale: Double = 1e6) {
            var bits = UInt64(bitPattern: Int64((value * scale).rounded()))
            for _ in 0..<8 {
                put(UInt8(bits & 0xFF))
                bits >>= 8
            }
        }
        for segment in segments {
            switch segment {
            case .line(let a, let b):
                put(0)
                [a.x, a.y, b.x, b.y].forEach { feed($0) }
            case .arc(let c, let r, let s, let e):
                put(1)
                [c.x, c.y, r].forEach { feed($0) }
                [s.radians, e.radians].forEach { feed($0, scale: 1e9) }
            case .spline(let curve):
                put(2)
                curve.poles.forEach { feed($0.x); feed($0.y) }
                curve.knots.forEach { feed($0, scale: 1e9) }
                curve.multiplicities.forEach { feed(Double($0)) }
            }
        }
        return hash
    }

    @Test func rectangleAndRoundedDigestsArePinned() throws {
        let rectangle = try OutlineChainer.chain(OutlineChainerTests.rectangle, tolerance: 0.01)
        #expect(Self.digest(rectangle.outer) == 0xE32C_441F_C5D7_03A1)
        let items = OutlineChainerTests.rounded
        let rounded = try OutlineChainer.chain(items, tolerance: 0.01)
        #expect(Self.digest(rounded.outer) == 0x6029_1B2D_C787_DBB2)
    }
}

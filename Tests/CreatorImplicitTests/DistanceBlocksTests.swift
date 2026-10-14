import CreatorGeometry
import Testing
@testable import CreatorImplicit

struct DistanceBlocksTests {
    @Test func aLinearFieldIsReproducedExactlyInsideTheGrid() {
        let blocks = BlocksFixture.make(origin: Vector3(-4, -4, -4), spacing: 0.5, blocks: 2) { 2 * $0.x - $0.y + 3 }
        for point in [Vector3(-3.2, 0.1, 1), Vector3(0.7, 2.2, -2.9), Vector3(2.4, -3.3, 3.1)] {
            #expect(abs(blocks.value(at: point) - (2 * point.x - point.y + 3)) < 1e-5, "at \(point)")
        }
    }

    @Test func outsideTheGridTheValueGrowsWithTheDistanceFromIt() {
        let blocks = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { _ in 5 }
        // Samples span 0 ... 7 on each axis.
        #expect(blocks.bounds == BoundingBox(min: .zero, max: Vector3(7, 7, 7)))
        #expect(abs(blocks.value(at: Vector3(10, 0, 0)) - 8) < 1e-9)
        #expect(abs(blocks.value(at: Vector3(10, 11, 7)) - (5 + 5.0.squareRoot() * 0 + (3 * 3 + 4 * 4).squareRoot())) < 1e-9)
    }

    @Test func aBlockThatIsNotStoredReadsItsBound() {
        let size = DistanceBlocks.blockSize
        var pool = [Float](repeating: 1, count: size * size * size)
        pool[0] = 1
        // Two blocks along x: the first stored, the second not (bound 9).
        let blocks = DistanceBlocks(origin: .zero, spacing: 1, blockCounts: [2, 1, 1], table: [0, -1], pool: pool, coarse: [0, 9], band: 3)
        #expect(blocks.storedBlockCount == 1)
        #expect(abs(blocks.value(at: Vector3(3, 3, 3)) - 1) < 1e-9)
        #expect(abs(blocks.value(at: Vector3(12, 3, 3)) - 9) < 1e-9)
        // Between the last stored sample (x = 7) and the first of the unstored block (x = 8) it blends.
        #expect(abs(blocks.value(at: Vector3(7.5, 3, 3)) - 5) < 1e-9)
    }

    @Test func sizesAndEquality() {
        let a = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }
        let b = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }
        #expect(a == a && a != b)
        #expect(a.estimatedBytes == 512 * 4 + 8 + 128 && a.blockLength == 8)
    }
}

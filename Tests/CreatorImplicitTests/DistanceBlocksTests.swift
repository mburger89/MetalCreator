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

    @Test func theSlopeBoundIsTheInterpolantsOwn() {
        let flat = BlocksFixture.make(origin: .zero, spacing: 0.5, blocks: 2) { $0.x }
        #expect(abs(flat.lipschitz - 1) < 1e-6)
        let steep = BlocksFixture.make(origin: .zero, spacing: 0.5, blocks: 2) { 3 * $0.x + 4 * $0.y }
        #expect(abs(steep.lipschitz - 5) < 1e-4)
        let constant = BlocksFixture.make(origin: .zero, spacing: 0.5, blocks: 1) { _ in 2 }
        #expect(constant.lipschitz == 1, "never below 1")
        // A ball's distance is a cone at its centre, whose cell reads a slope of √3; cells near the surface read about 1.
        let everywhere = BlocksFixture.make(origin: Vector3(-16, -16, -16), spacing: 1, blocks: 4) { $0.length - 9 }
        #expect(everywhere.lipschitz > 1.7 && everywhere.lipschitz < 1.75)
        let nearSurface = BlocksFixture.make(origin: Vector3(-16, -16, -16), spacing: 1, blocks: 4, band: 6) { $0.length - 9 }
        #expect(nearSurface.lipschitz >= 1 && nearSurface.lipschitz < 1.3)
    }

    @Test func sizesAndEquality() {
        let a = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }
        let b = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }
        #expect(a == a && a != b)
        #expect(a.estimatedBytes == 512 * 4 + 8 + 128 && a.blockLength == 8)
    }
}

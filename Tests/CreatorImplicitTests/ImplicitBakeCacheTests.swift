import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorImplicit

struct ImplicitBakeCacheTests {
    let kernel = FakeKernel()
    let tag = NodeTag(node: NodeID(), item: 0)

    func block(_ size: Double) async throws -> Solid {
        try await kernel.extrude(.rectangle(width: size, height: size, plane: .xy), distance: size, mode: .oneSided, tag: tag)
    }

    @Test func aSolidBakesToItsSignedDistance() async throws {
        let cache = ImplicitBakeCache()
        let baked = try await cache.baked(for: try await block(10), tolerance: 0.01, kernel: kernel)
        // A 10 mm cube standing on z = 0, centred on x and y. Near a face the distance is exact; at the middle, where the true
        // distance has a ridge, the interpolation cuts it a little short.
        #expect(abs(baked.blocks.value(at: Vector3(0, 0, 0.5)) + 0.5) < 0.01)
        #expect(abs(baked.blocks.value(at: Vector3(8, 0, 5)) - 3) < 0.01)
        #expect(abs(baked.blocks.value(at: Vector3(0, 0, 5)) + 5) < 0.5)
        #expect(baked.seconds > 0 && baked.spacing >= 0.4 && baked.tolerance == 0.01)
    }

    @Test func theSameSolidAndToleranceBakeOnce() async throws {
        let cache = ImplicitBakeCache()
        let solid = try await block(10)
        let first = try await cache.baked(for: solid, tolerance: 0.01, kernel: kernel)
        let second = try await cache.baked(for: solid, tolerance: 0.01, kernel: kernel)
        #expect(first.blocks === second.blocks)
        #expect(await cache.bakeCount == 1)
        _ = try await cache.baked(for: solid, tolerance: 0.02, kernel: kernel)
        _ = try await cache.baked(for: try await block(10), tolerance: 0.01, kernel: kernel)
        #expect(await cache.bakeCount == 3)
        #expect(await cache.entryCount == 3)
    }

    @Test func theLeastRecentlyUsedEntriesGoWhenTheCacheIsFull() async throws {
        let cache = ImplicitBakeCache(capacity: 1)
        let (a, b) = (try await block(10), try await block(12))
        let first = try await cache.baked(for: a, tolerance: 0.01, kernel: kernel)
        _ = try await cache.baked(for: b, tolerance: 0.01, kernel: kernel)
        #expect(await cache.entryCount == 1, "only the newest stays")
        let again = try await cache.baked(for: a, tolerance: 0.01, kernel: kernel)
        #expect(first.blocks !== again.blocks)
        #expect(await cache.bakeCount == 3)
    }
}

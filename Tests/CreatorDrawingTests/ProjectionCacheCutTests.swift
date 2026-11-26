import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Projection cache cuts")
struct ProjectionCacheCutTests {
    typealias Base = ProjectionCacheTests

    // MARK: Cuts

    static let cutter = SectionCutter(frame: Base.front, points: [Vector2(-10, 5), Vector2(10, 5)], viewing: Vector2(0, 1))

    @Test func aCutIsMadeOnce() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let solid = try await Base.box(kernel)
        await kernel.setSectionCutHook { part, _, _ in part }
        let first = try await cache.sectionCut(of: solid, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel)
        let second = try await cache.sectionCut(of: solid, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel)
        #expect(first.remainder === second.remainder)
        #expect(first.regions == second.regions)
        #expect(await cache.cutCalls == 1)
    }

    @Test func cutsAreKeyedByCutter() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let solid = try await Base.box(kernel)
        await kernel.setSectionCutHook { part, _, _ in part }
        _ = try await cache.sectionCut(of: solid, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel)
        let moved = SectionCutter(frame: Base.front, points: [Vector2(-10, 6), Vector2(10, 6)], viewing: Vector2(0, 1))
        _ = try await cache.sectionCut(of: solid, index: 0, cutter: moved, tolerance: 0.01, kernel: kernel)
        #expect(await cache.cutCalls == 2)
    }

    @Test func cutsAreEvicted() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache(limit: 1)
        let a = try await Base.box(kernel)
        let b = try await Base.box(kernel)
        await kernel.setSectionCutHook { part, _, _ in part }
        _ = try await cache.sectionCut(of: a, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel)
        _ = try await cache.sectionCut(of: b, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel)
        _ = try await cache.sectionCut(of: b, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel)
        #expect(await cache.cutCalls == 2)
        _ = try await cache.sectionCut(of: a, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel)
        #expect(await cache.cutCalls == 3)
    }
}

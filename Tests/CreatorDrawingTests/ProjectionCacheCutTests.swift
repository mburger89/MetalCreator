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

    private actor Observed {
        var entered = false
        var sawCancellation = false
        func enter() { entered = true }
        func cancelled() { sawCancellation = true }
    }

    @Test func aCancelledCutIsCancelledInTheKernelAndNeverCached() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let solid = try await Base.box(kernel)
        let observed = Observed()
        let first = Self.cutter
        let second = SectionCutter(frame: Base.front, points: [Vector2(-10, 6), Vector2(10, 6)], viewing: Vector2(0, 1))
        await kernel.setSectionCutHook { part, line, _ in
            guard line == first else { return part }
            await observed.enter()
            for _ in 0..<400 {
                if Task.isCancelled {
                    await observed.cancelled()
                    throw CancellationError()
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            return part
        }
        let older = Task { try await cache.sectionCut(of: solid, index: 0, cutter: first, tolerance: 0.01, kernel: kernel) }
        while await !observed.entered { await Task.yield() }
        let newer = Task { try await cache.sectionCut(of: solid, index: 0, cutter: second, tolerance: 0.01, kernel: kernel) }
        older.cancel()
        _ = try await newer.value
        _ = await older.result
        #expect(await observed.sawCancellation, "the kernel's cut for the abandoned line was cancelled")
        #expect(await cache.cutCalls == 2)
        let all = await cache.count
        #expect(all == 0)
        _ = try await cache.sectionCut(of: solid, index: 0, cutter: second, tolerance: 0.01, kernel: kernel)
        #expect(await cache.cutCalls == 2, "only the second cut was cached")
    }

    @Test func aCutSharedByTwoWaitersSurvivesOneLeaving() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let solid = try await Base.box(kernel)
        let observed = Observed()
        await kernel.setSectionCutHook { part, _, _ in
            await observed.enter()
            for _ in 0..<20 { try await Task.sleep(for: .milliseconds(5)) }
            return part
        }
        let one = Task { try await cache.sectionCut(of: solid, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel) }
        while await !observed.entered { await Task.yield() }
        let two = Task { try await cache.sectionCut(of: solid, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel) }
        one.cancel()
        _ = try await two.value
        #expect(await cache.cutCalls == 1)
    }
}

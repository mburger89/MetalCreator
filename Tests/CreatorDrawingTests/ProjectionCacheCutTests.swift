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
        #expect(await cache.cachedCutCount == 1, "the abandoned cut was never cached")
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
        // Cancel only once the second caller has provably joined the flight, or `one`'s leaving could win the race.
        let deadline = ContinuousClock.now + .seconds(10)
        while await cache.cutWaiterCount < 2 {
            try #require(ContinuousClock.now < deadline, "the second caller never joined the cut")
            await Task.yield()
        }
        one.cancel()
        _ = try await two.value
        #expect(await cache.cutCalls == 1)
    }

    /// A caller that is cancelled while it shares a cut with another leaves at once (it does not wait for the kernel), and the cut
    /// goes on for the one still waiting and is cached.
    @Test func aCancelledSharerReturnsAtOnceWhileTheCutGoesOn() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let solid = try await Base.box(kernel)
        let gate = SuspendingGate()
        await kernel.setSectionCutHook { part, _, _ in
            await gate.hold()
            return part
        }
        let one = Task { try await cache.sectionCut(of: solid, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel) }
        await gate.waitForEntries(1)
        let two = Task { try await cache.sectionCut(of: solid, index: 0, cutter: Self.cutter, tolerance: 0.01, kernel: kernel) }
        let deadline = ContinuousClock.now + .seconds(10)
        while await cache.cutWaiterCount < 2 {
            try #require(ContinuousClock.now < deadline, "the second caller never joined the cut")
            await Task.yield()
        }
        one.cancel()
        // The kernel's cut is still held, so a caller that came back did so without waiting for it.
        let outcome = await one.result
        guard case .failure(let error) = outcome else {
            Issue.record("the cancelled caller returned a piece")
            await gate.open()
            return
        }
        #expect(error is CancellationError)
        #expect(await cache.cutCalls == 1)
        #expect(await cache.cachedCutCount == 0, "the cut has not finished")
        await gate.open()
        let piece = try await two.value
        #expect(piece.remainder === solid)
        #expect(await cache.cachedCutCount == 1, "the cut went on and was cached")
        #expect(await cache.cutCalls == 1)
    }
}

import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Projection cache")
struct ProjectionCacheTests {
    static let front = ProjectionFrame(direction: Vector3(0, 1, 0), up: Vector3(0, 0, 1))
    static let side = ProjectionFrame(direction: Vector3(1, 0, 0), up: Vector3(0, 0, 1))
    static let tag = NodeTag(node: NodeID(), item: 0)
    static let options = ProjectionOptions(tolerance: 0.01)

    static func box(_ kernel: FakeKernel, _ size: Double = 10) async throws -> Solid {
        try await kernel.extrude(
            .rectangle(width: size, height: size, plane: .xy), distance: size, mode: .oneSided,
            tag: NodeTag(node: NodeID(), item: 0))
    }

    static func project(
        _ cache: ProjectionCache, _ solids: [Solid], _ kernel: FakeKernel, frame: ProjectionFrame = front,
        options: ProjectionOptions = options
    ) async throws -> Projection2D {
        try await cache.projection(
            of: solids, curves: [], compoundTag: tag, frame: frame, options: options, kernel: kernel)
    }

    @Test func aRepeatIsAHit() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let solid = try await Self.box(kernel)
        let first = try await Self.project(cache, [solid], kernel)
        let second = try await Self.project(cache, [solid], kernel)
        #expect(first == second)
        #expect(await cache.kernelCalls == 1)
        #expect(await cache.count == 1)
    }

    @Test func identicalRequestsShareOneKernelCall() async throws {
        let kernel = FakeKernel()
        let gate = SuspendingGate()
        await kernel.setProjectionHook { await gate.hold() }
        let cache = ProjectionCache()
        let solid = try await Self.box(kernel)
        let a = Task { try await Self.project(cache, [solid], kernel) }
        await gate.waitForEntries(1)
        let b = Task { try await Self.project(cache, [solid], kernel) }
        await Self.waitForWaiters(2, in: cache)
        await gate.open()
        let (first, second) = try await (a.value, b.value)
        #expect(first == second)
        #expect(await cache.kernelCalls == 1)
    }

    @Test func aDifferentFrameOrToleranceMisses() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let solid = try await Self.box(kernel)
        _ = try await Self.project(cache, [solid], kernel)
        _ = try await Self.project(cache, [solid], kernel, frame: Self.side)
        _ = try await Self.project(cache, [solid], kernel, options: ProjectionOptions(tolerance: 0.005))
        #expect(await cache.kernelCalls == 3)
        #expect(await cache.count == 3)
    }

    @Test func aNewSolidIdentityMisses() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let a = try await Self.box(kernel)
        let b = try await Self.box(kernel)
        _ = try await Self.project(cache, [a], kernel)
        _ = try await Self.project(cache, [b], kernel)
        #expect(await cache.kernelCalls == 2)
    }

    @Test func theLimitEvictsLeastRecentlyUsed() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache(limit: 1024)
        var solids: [Solid] = []
        for _ in 0..<6 { solids.append(try await Self.box(kernel)) }
        _ = try await Self.project(cache, [solids[0]], kernel)
        _ = try await Self.project(cache, [solids[1]], kernel)
        // Reading the first again makes the second the least recently used.
        _ = try await Self.project(cache, [solids[0]], kernel)
        for solid in solids[2...] { _ = try await Self.project(cache, [solid], kernel) }
        #expect(await cache.bytesUsed <= 1024)
        #expect(await cache.count < 6)
        let calls = await cache.kernelCalls
        _ = try await Self.project(cache, [solids[5]], kernel)
        #expect(await cache.kernelCalls == calls)
        // Whichever the limit left, the touched first outlives the untouched second.
        _ = try await Self.project(cache, [solids[0]], kernel)
        let afterFirst = await cache.kernelCalls
        _ = try await Self.project(cache, [solids[1]], kernel)
        #expect(await cache.kernelCalls == afterFirst + 1)
    }

    @Test func theNewestIsKeptEvenAloneOverTheLimit() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache(limit: 1)
        let a = try await Self.box(kernel)
        let b = try await Self.box(kernel)
        _ = try await Self.project(cache, [a], kernel)
        _ = try await Self.project(cache, [b], kernel)
        #expect(await cache.count == 1)
        _ = try await Self.project(cache, [b], kernel)
        #expect(await cache.kernelCalls == 2)
    }

    @Test func removeAllEmpties() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let solid = try await Self.box(kernel)
        _ = try await Self.project(cache, [solid], kernel)
        await cache.removeAll()
        #expect(await cache.count == 0)
        #expect(await cache.bytesUsed == 0)
    }

    @Test func aFailureIsNotCached() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let solid = try await Self.box(kernel)
        await kernel.setProjectionHook { throw KernelError.invalidInput("no") }
        await #expect(throws: KernelError.self) { try await Self.project(cache, [solid], kernel) }
        #expect(await cache.count == 0)
        await kernel.setProjectionHook(nil)
        _ = try await Self.project(cache, [solid], kernel)
        #expect(await cache.count == 1)
        // A compound that throws is not cached either.
        let other = try await Self.box(kernel)
        await #expect(throws: KernelError.self) { try await Self.project(cache, [solid, other], kernel) }
        #expect(await cache.count == 1)
    }

    @Test func cancellingOneWaiterLeavesTheOther() async throws {
        let kernel = FakeKernel()
        let gate = SuspendingGate()
        await kernel.setProjectionHook { await gate.hold() }
        let cache = ProjectionCache()
        let solid = try await Self.box(kernel)
        let a = Task { try await Self.project(cache, [solid], kernel) }
        await gate.waitForEntries(1)
        let b = Task { try await Self.project(cache, [solid], kernel) }
        await Self.waitForWaiters(2, in: cache)
        a.cancel()
        // The cancelled waiter leaves at once, while the build still holds.
        await #expect(throws: CancellationError.self) { try await a.value }
        await gate.open()
        let result = try await b.value
        #expect(!result.lines.isEmpty)
        #expect(await cache.count == 1)
    }

    @Test func cancellingEveryWaiterCancelsTheBuild() async throws {
        let kernel = FakeKernel()
        let gate = SuspendingGate()
        let seen = CancellationFlag()
        await kernel.setProjectionHook {
            await gate.hold()
            if Task.isCancelled { await seen.set() }
        }
        let cache = ProjectionCache()
        let solid = try await Self.box(kernel)
        let a = Task { try await Self.project(cache, [solid], kernel) }
        await gate.waitForEntries(1)
        let b = Task { try await Self.project(cache, [solid], kernel) }
        await Self.waitForWaiters(2, in: cache)
        a.cancel()
        b.cancel()
        await #expect(throws: CancellationError.self) { try await a.value }
        await #expect(throws: CancellationError.self) { try await b.value }
        #expect(await cache.waitingCount == 0)
        await gate.open()
        await seen.waitUntilSet()
        #expect(await cache.count == 0)
        // The next request builds again.
        await kernel.setProjectionHook(nil)
        _ = try await Self.project(cache, [solid], kernel)
        #expect(await cache.count == 1)
        #expect(await cache.kernelCalls == 2)  // the cancelled build counted 1; the rebuild is the 2nd
    }

    static func waitForWaiters(_ count: Int, in cache: ProjectionCache) async {
        while await cache.waitingCount < count { await Task.yield() }
    }

    @Test func twoConcurrentMultiSolidRequestsCompoundOnce() async throws {
        let kernel = FakeKernel()
        let gate = SuspendingGate()
        let merged = try await Self.box(kernel, 20)
        await kernel.setCompoundHook { _ in merged }
        await kernel.setProjectionHook { await gate.hold() }
        let cache = ProjectionCache()
        let solids = [try await Self.box(kernel), try await Self.box(kernel)]
        let a = Task { try await Self.project(cache, solids, kernel) }
        await gate.waitForEntries(1)
        let b = Task { try await Self.project(cache, solids, kernel) }
        await Self.waitForWaiters(2, in: cache)
        await gate.open()
        _ = try await (a.value, b.value)
        #expect(await cache.compoundCalls == 1)
        #expect(await cache.kernelCalls == 1)
    }
}

actor CancellationFlag {
    private var isSet = false
    private var watchers: [CheckedContinuation<Void, Never>] = []

    func set() {
        isSet = true
        for watcher in watchers { watcher.resume() }
        watchers.removeAll()
    }

    func waitUntilSet() async {
        if isSet { return }
        await withCheckedContinuation { watchers.append($0) }
    }
}

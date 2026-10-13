import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Fields spec §2.2: kernel distances cached per distance source and point set, 64 MB, least recently used first.
struct FieldDistanceCacheTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    func cube(_ kernel: FakeKernel) async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
    }

    func points(_ count: Int, offset: Double = 0) -> [Vector3] {
        (0..<count).map { Vector3(Double($0) + offset, 1, 2) }
    }

    /// Measures 10 points starting `offset` along x, signed.
    func measure(_ cache: FieldDistanceCache, _ kernel: FakeKernel, _ target: DistanceTarget, offset: Double) async throws {
        _ = try await cache.distances(from: points(10, offset: offset), to: target, signed: true, kernel: kernel)
    }

    struct Stats: Equatable {
        var hits: Int, misses: Int, entries: Int, bytes: Int
    }

    func stats(_ cache: FieldDistanceCache) async -> Stats {
        Stats(hits: await cache.hits, misses: await cache.misses, entries: await cache.entryCount, bytes: await cache.totalBytes)
    }

    func kernelCalls(_ kernel: FakeKernel) async -> Int {
        await kernel.operationLog.filter { $0 == "distances" }.count
    }

    @Test func theSameSourceAndPointsAreMeasuredOnce() async throws {
        let kernel = FakeKernel()
        let cache = FieldDistanceCache()
        let target = DistanceTarget.solid(try await cube(kernel))
        let first = try await cache.distances(from: points(10), to: target, signed: true, kernel: kernel)
        let second = try await cache.distances(from: points(10), to: target, signed: true, kernel: kernel)
        #expect(first == second)
        #expect(await kernelCalls(kernel) == 1)
        let seen = await stats(cache)
        #expect(seen.hits == 1 && seen.misses == 1 && seen.entries == 1)
    }

    @Test func otherPointsAnotherSolidOrAnotherSignAreMisses() async throws {
        let kernel = FakeKernel()
        let cache = FieldDistanceCache()
        let solid = try await cube(kernel)
        _ = try await cache.distances(from: points(10), to: .solid(solid), signed: true, kernel: kernel)
        _ = try await cache.distances(from: points(10, offset: 0.5), to: .solid(solid), signed: true, kernel: kernel)
        _ = try await cache.distances(from: points(10), to: .solid(try await cube(kernel)), signed: true, kernel: kernel)
        _ = try await cache.distances(from: points(10), to: .solid(solid), signed: false, kernel: kernel)
        _ = try await cache.distances(from: points(9), to: .solid(solid), signed: true, kernel: kernel)
        #expect(await kernelCalls(kernel) == 5)
        let seen = await stats(cache)
        #expect(seen.hits == 0 && seen.entries == 5)
    }

    @Test func signIsIgnoredForEdgesSoItNeverSplitsTheirEntry() async throws {
        let kernel = FakeKernel()
        let cache = FieldDistanceCache()
        let edges = DistanceTarget.edges(EdgeSet(solid: try await cube(kernel), edges: [EdgeID(0), EdgeID(1)]))
        _ = try await cache.distances(from: points(4), to: edges, signed: true, kernel: kernel)
        _ = try await cache.distances(from: points(4), to: edges, signed: false, kernel: kernel)
        #expect(await kernelCalls(kernel) == 1)
    }

    @Test func aDroppedSolidsIdentityIsNeverReusedByTheNextOne() async throws {
        let kernel = FakeKernel()
        let cache = FieldDistanceCache()
        for _ in 0..<40 {
            // Each solid is let go as soon as it is measured, so its address is free for the next to land on.
            let target = DistanceTarget.solid(try await cube(kernel))
            _ = try await cache.distances(from: points(5), to: target, signed: true, kernel: kernel)
        }
        #expect(await kernelCalls(kernel) == 40, "no solid was taken for an earlier one")
        #expect(await cache.hits == 0)
    }

    @Test func aSelectionIsASetSoOrderAndRepeatsDoNotMatter() async throws {
        let kernel = FakeKernel()
        let cache = FieldDistanceCache()
        let solid = try await cube(kernel)
        _ = try await cache.distances(from: points(4), to: .edges(EdgeSet(solid: solid, edges: [EdgeID(1), EdgeID(0)])), signed: false,
                                      kernel: kernel)
        _ = try await cache.distances(from: points(4), to: .edges(EdgeSet(solid: solid, edges: [EdgeID(0), EdgeID(1), EdgeID(0)])),
                                      signed: false, kernel: kernel)
        #expect(await kernelCalls(kernel) == 1)
    }

    @Test func theLeastRecentlyUsedEntryGoesFirst() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        // One entry of 10 points is 10 × 24 + 10 × 8 + 128 bytes plus the solid it keeps alive: room for three.
        let entry = 10 * 24 + 10 * 8 + 128 + solid.estimatedBytes
        let cache = FieldDistanceCache(budgetBytes: 3 * entry + 10)
        let target = DistanceTarget.solid(solid)
        for offset in [0.0, 1, 2] { try await measure(cache, kernel, target, offset: offset) }
        try await measure(cache, kernel, target, offset: 0)  // offset 0 is now the newest
        try await measure(cache, kernel, target, offset: 3)  // evicts offset 1
        let seen = await stats(cache)
        #expect(seen.entries == 3 && seen.bytes == 3 * entry)
        await kernel.clearLog()
        for offset in [0.0, 2, 3] { try await measure(cache, kernel, target, offset: offset) }
        #expect(await kernelCalls(kernel) == 0, "0, 2 and 3 are still there")
        try await measure(cache, kernel, target, offset: 1)
        #expect(await kernelCalls(kernel) == 1, "1 was the least recently used")
    }

    @Test func aResultBiggerThanTheBudgetIsReturnedButNotKept() async throws {
        let kernel = FakeKernel()
        let cache = FieldDistanceCache(budgetBytes: 1000)
        let target = DistanceTarget.solid(try await cube(kernel))
        let found = try await cache.distances(from: points(100), to: target, signed: true, kernel: kernel)
        #expect(found.count == 100)
        #expect(await stats(cache) == Stats(hits: 0, misses: 1, entries: 0, bytes: 0))
    }

    @Test func anEntryCountsTheSolidItKeepsAlive() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        let cache = FieldDistanceCache()
        _ = try await cache.distances(from: points(1), to: .solid(solid), signed: true, kernel: kernel)
        #expect(await cache.totalBytes == 1 * 24 + 1 * 8 + 128 + solid.estimatedBytes)
        // One point, but the solid alone fills this budget: the result is returned and not kept, so the solid is not pinned.
        let small = FieldDistanceCache(budgetBytes: solid.estimatedBytes)
        let found = try await small.distances(from: points(1), to: .solid(solid), signed: true, kernel: kernel)
        #expect(found.count == 1)
        #expect(await stats(small) == Stats(hits: 0, misses: 1, entries: 0, bytes: 0))
    }

    /// A slider drag upstream: a new solid every step and a few points each. The cache keeps those solids alive, so it must
    /// count them: the oldest let go once the budget is reached, however few points an entry holds.
    @Test func solidsKeptAliveByEntriesStayWithinTheBudget() async throws {
        let kernel = FakeKernel()
        let probe = try await cube(kernel)
        let entry = 1 * 24 + 1 * 8 + 128 + probe.estimatedBytes
        let cache = FieldDistanceCache(budgetBytes: 5 * entry)
        for _ in 0..<50 {
            _ = try await cache.distances(from: points(1), to: .solid(try await cube(kernel)), signed: true, kernel: kernel)
        }
        let seen = await stats(cache)
        #expect(seen.entries == 5 && seen.bytes == 5 * entry, "50 solids were measured and 5 are kept alive")
    }

    @Test func theDefaultBudgetIsSixtyFourMegabytes() async {
        #expect(FieldDistanceCache.defaultBudgetBytes == 64 * 1024 * 1024)
        #expect(await FieldDistanceCache().budgetBytes == 64 * 1024 * 1024)
    }

    @Test func aCancelledMeasurementCachesNothing() async throws {
        let kernel = FakeKernel()
        let cache = FieldDistanceCache()
        let target = DistanceTarget.solid(try await cube(kernel))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cache.distances(from: points(10), to: target, signed: true, kernel: kernel)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await stats(cache) == Stats(hits: 0, misses: 1, entries: 0, bytes: 0))
    }

    @Test func aKernelErrorPassesThroughAndCachesNothing() async throws {
        let kernel = FakeKernel()
        let cache = FieldDistanceCache()
        let solid = try await cube(kernel)
        await #expect(throws: KernelError.invalidInput("No edges are selected to measure to.")) {
            try await cache.distances(from: points(2), to: .edges(EdgeSet(solid: solid, edges: [])), signed: false, kernel: kernel)
        }
        #expect(await stats(cache).entries == 0)
    }

    @Test func clearForgetsEverything() async throws {
        let kernel = FakeKernel()
        let cache = FieldDistanceCache()
        let target = DistanceTarget.solid(try await cube(kernel))
        _ = try await cache.distances(from: points(10), to: target, signed: true, kernel: kernel)
        await cache.clear()
        #expect(await stats(cache) == Stats(hits: 0, misses: 1, entries: 0, bytes: 0))
        _ = try await cache.distances(from: points(10), to: target, signed: true, kernel: kernel)
        #expect(await kernelCalls(kernel) == 2)
    }

    // MARK: the evaluator owns one

    @Test func everyContextOfOneEvaluatorSharesItsCache() async throws {
        let registry = NodeRegistry([CacheProbeNode.self])
        let nodes = [registry.makeNode(CacheProbeNode.typeID), registry.makeNode(CacheProbeNode.typeID)]
        let graph = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: [])
        let evaluator = Evaluator(registry: registry, kernel: FakeKernel())
        let report = try await evaluator.evaluate(graph, demand: Set(nodes.map(\.id)))
        let seen = nodes.compactMap { report.results[$0.id]?.outputs?["id"]?.items.first }
        let ids = seen.compactMap { scalar -> Int? in if case .integer(let value) = scalar { value } else { nil } }
        let want = ObjectIdentifier(evaluator.fieldDistances).hashValue
        #expect(ids == [want, want])
    }

    @Test func aContextBuiltByHandGetsAFreshCache() {
        let node = Node(typeID: "x", typeVersion: 1, name: "x", inputValues: [:], position: .zero, isOutput: false)
        let a = EvalContext(node: node, item: 0, parameters: [:]), b = EvalContext(node: node, item: 0, parameters: [:])
        #expect(a.fieldDistances !== b.fieldDistances)
    }
}

/// Reports which cache its context carries.
enum CacheProbeNode: NodeDefinition {
    static let typeID = "test.cacheProbe"
    static let displayName = "Cache Probe"
    static let category = NodeCategory.fields
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("id", .integer)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["id": .integer(ObjectIdentifier(context.fieldDistances).hashValue)])
    }
}

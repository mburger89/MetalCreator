import CreatorGeometry
import Testing
@testable import CreatorApp

/// Over 200,000 vertices a deterministic subset is sampled and the rest take their nearest sampled vertex's value (D14).
struct CoarseSamplingTests {
    @Test func theLimitIsTwoHundredThousand() {
        #expect(CoarseSampling.vertexLimit == 200_000)
    }

    @Test func aMeshWithinTheLimitIsSampledWholeInOrder() {
        #expect(CoarseSampling.sampledIndices(count: 5, limit: 5) == [0, 1, 2, 3, 4])
        #expect(CoarseSampling.sampledIndices(count: 0, limit: 5).isEmpty)
        #expect(CoarseSampling.sampledIndices(count: 3, limit: 5) == [0, 1, 2])
    }

    @Test func aBiggerOneGetsExactlyTheLimitEvenlySpacedAndNeverTwice() {
        #expect(CoarseSampling.sampledIndices(count: 10, limit: 4) == [0, 2, 5, 7])
        let many = CoarseSampling.sampledIndices(count: 200_001)
        #expect(many.count == 200_000 && Set(many).count == 200_000 && many.first == 0 && (many.last ?? 0) < 200_001)
        #expect(many == CoarseSampling.sampledIndices(count: 200_001), "deterministic")
    }

    @Test func everyVertexTakesItsNearestSampledVerticesValueTiesToTheLowerOne() throws {
        let positions = (0..<10).map { Vector3(Double($0), 0, 0) }
        let indices = [0, 2, 5, 7]
        let values = try CoarseSampling.expand(positions: positions, sampled: indices, values: [0, 20, 50, 70])
        #expect(values == [0, 0, 20, 20, 50, 50, 50, 70, 70, 70], "1 → 0 (tie with 2), 3 → 2, 4 → 5, 6 → 5 (tie with 7), 8 and 9 → 7")
    }

    @Test func theGridAgreesWithABruteForceSearchOnAScatterOfPoints() throws {
        var random = SplitMix(seed: 11)
        let positions = (0..<4_000).map { _ in Vector3(random.next() * 100, random.next() * 60, random.next() * 8) }
        let indices = CoarseSampling.sampledIndices(count: positions.count, limit: 500)
        let values = indices.map { Double($0) }
        let expanded = try CoarseSampling.expand(positions: positions, sampled: indices, values: values)
        #expect(expanded.count == positions.count)
        for vertex in stride(from: 0, to: positions.count, by: 37) {
            func distance(_ slot: Int) -> Double { (positions[indices[slot]] - positions[vertex]).length }
            var best = 0
            for slot in indices.indices where distance(slot) < distance(best) { best = slot }
            #expect(expanded[vertex] == Float(values[best]), "vertex \(vertex)")
        }
        #expect(indices.allSatisfy { expanded[$0] == Float($0) }, "a sampled vertex keeps its own value")
    }

    @Test func nothingSampledOrAWrongCountIsRefusedOrEmpty() throws {
        #expect(try CoarseSampling.expand(positions: [], sampled: [], values: []).isEmpty)
        #expect(try CoarseSampling.expand(positions: [.zero, .unitX], sampled: [1], values: [4]) == [4, 4])
        let whole = try CoarseSampling.expand(positions: [.zero, .unitX], sampled: [0, 1], values: [1, 2])
        #expect(whole == [1, 2])
    }

    @Test func aCancelledExpansionStops() async {
        let positions = (0..<30_000).map { Vector3(Double($0), 0, 0) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try CoarseSampling.expand(positions: positions, sampled: [0, 29_999], values: [1, 2])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

/// A small deterministic generator for the scatter test (not the app's `SeededRandom`, which is internal to CreatorNodes).
struct SplitMix {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    /// The next number in 0 ..< 1.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) * 0x1p-53
    }
}

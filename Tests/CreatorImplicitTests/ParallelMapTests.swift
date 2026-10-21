import Testing
@testable import CreatorImplicit

struct ParallelMapTests {
    @Test func itGivesWhatMapGivesInTheSameOrder() async throws {
        for count in [0, 1, 255, 256, 257, 10_000, 100_003] {
            let items = Array(0..<count)
            let mapped = try await ParallelMap.map(items) { chunk in chunk.map { $0 &* 31 &+ 7 } }
            #expect(mapped == items.map { $0 &* 31 &+ 7 }, "\(count) items")
        }
    }

    @Test func aCancelledMapThrows() async {
        let task = Task { () async throws -> [Int] in
            try await Task.sleep(for: .milliseconds(200))
            return try await ParallelMap.map(Array(0..<10_000)) { $0 }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

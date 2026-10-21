import Testing
@testable import CreatorImplicit

struct ParallelMapTests {
    @Test func itGivesWhatMapGivesInTheSameOrder() {
        for count in [0, 1, 255, 256, 257, 10_000, 100_003] {
            let items = Array(0..<count)
            #expect(ParallelMap.map(items) { $0 &* 31 &+ 7 } == items.map { $0 &* 31 &+ 7 }, "\(count) items")
        }
    }
}

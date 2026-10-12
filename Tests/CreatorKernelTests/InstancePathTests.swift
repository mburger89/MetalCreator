import Testing
@testable import CreatorKernel

/// Patterns spec §6: an instance's path is one tag item. A flat path is its index (so picks saved before trees still
/// name the same instance); a deeper one is packed into a negative number and read back.
struct InstancePathTests {
    @Test(arguments: [0, 1, 7, 1_999, 40_000])
    func aFlatPathIsItsOwnIndex(_ index: Int) {
        #expect(InstancePath.item(for: [index]) == index)
        #expect(InstancePath.indices(ofItem: index) == [index])
        #expect(InstancePath.text(index) == "{\(index)}")
    }

    @Test(arguments: [[0, 0], [0, 3], [3, 0], [1, 2, 3], [2, 0, 7, 9], [32_767, 32_767], [32_767, 0, 0, 32_767]])
    func aDeeperPathRoundTripsThroughOneNegativeNumber(_ indices: [Int]) throws {
        let item = try #require(InstancePath.item(for: indices))
        #expect(item < 0)
        #expect(InstancePath.indices(ofItem: item) == indices)
        #expect(InstancePath.text(item) == InstancePath.text(indices: indices))
    }

    @Test func textWritesPathsWithSemicolons() {
        #expect(InstancePath.text(indices: [0, 3]) == "{0;3}")
        #expect(InstancePath.text(InstancePath.item(for: [1, 0, 4]) ?? 0) == "{1;0;4}")
    }

    @Test func noTwoPathsShareAnItem() {
        var seen: [Int: [Int]] = [:]
        for first in 0..<6 {
            for second in 0..<6 {
                for indices in [[first], [first, second], [first, second, 0], [0, first, second]] {
                    let item = InstancePath.item(for: indices)
                    if let item, let other = seen[item] { #expect(other == indices, "\(other) and \(indices) share \(item)") }
                    if let item { seen[item] = indices }
                }
            }
        }
    }

    @Test(arguments: [[], [-1], [0, -1], [0, 32_768], [1, 2, 3, 4, 5]])
    func aPathThatCannotBeNamedGivesNoItem(_ indices: [Int]) {
        #expect(InstancePath.item(for: indices) == nil)
    }

    @Test func anInvalidNegativeNumberIsWrittenAsItIs() {
        #expect(InstancePath.indices(ofItem: -5) == nil)
        #expect(InstancePath.indices(ofItem: Int.min) == nil)
        #expect(InstancePath.text(-5) == "{-5}")
    }
}

import Testing
@testable import CreatorGraph

struct TreePathTests {
    @Test func pathsAreWrittenWithBracesAndSemicolons() {
        #expect(TreePath([0, 3]).description == "{0;3}")
        #expect(TreePath([1, 0, 4]).description == "{1;0;4}")
        #expect(TreePath().description == "{}")
    }

    @Test(arguments: [("{0;3}", [0, 3]), (" { 1 ; 0 ; 4 } ", [1, 0, 4]), ("{7}", [7]), ("{}", [])])
    func goodTextParses(_ text: String, _ indices: [Int]) {
        #expect(TreePath(parsing: text)?.indices == indices)
    }

    @Test(arguments: ["", "0;3", "{0;}", "{;1}", "{-1}", "{a}", "{0,3}", "{0;3", "0;3}", "{1.5}"])
    func badTextIsNil(_ text: String) {
        #expect(TreePath(parsing: text) == nil)
    }

    @Test func pathsOrderLevelByLevel() {
        #expect(TreePath([0, 9]) < TreePath([1, 0]))
        #expect(TreePath([1]) < TreePath([1, 0]))
        #expect([TreePath([1, 0]), TreePath([0, 3]), TreePath([0, 1])].sorted().map(\.description) == ["{0;1}", "{0;3}", "{1;0}"])
    }

    @Test func appendingAddsALevel() {
        #expect(TreePath([2]).appending(5) == TreePath([2, 5]))
    }
}

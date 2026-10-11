import Foundation
import Testing
@testable import CreatorGraph

struct TreeAccessTests {
    let specs = [SocketSpec("a", .number), SocketSpec("whole", .any, access: .tree)]

    @Test func aTreeSocketGetsTheWholeTreeAndDoesNotBroadcast() throws {
        let plan = BroadcastPlan.make(inputs: ["whole": .tree(rows([0, 1], [2, 3]))], specs: specs)
        #expect(plan.iterations == 1)
        #expect(plan.isSingle)
        #expect(try plan.inputs(at: 0).tree("whole").outline == "[[0,1],[2,3]]")
    }

    @Test func aFlatListOnATreeSocketIsATreeOfDepthOne() throws {
        let plan = BroadcastPlan.make(inputs: ["whole": .list(ints(1, 2, 3))], specs: specs)
        let tree = try plan.inputs(at: 0).tree("whole")
        #expect(tree.depth == 1)
        #expect(tree.outline == "[1,2,3]")
    }

    @Test func oneItemOnATreeSocketIsAListOfOne() throws {
        let plan = BroadcastPlan.make(inputs: ["whole": .one(.integer(7))], specs: specs)
        #expect(try plan.inputs(at: 0).tree("whole").outline == "[7]")
    }

    @Test func itemSocketsStillBroadcastBesideATreeSocket() throws {
        let plan = BroadcastPlan.make(inputs: ["a": .list([.number(1), .number(2)]), "whole": .tree(rows([5]))], specs: specs)
        #expect(plan.iterations == 2)
        #expect(try plan.inputs(at: 1).number("a") == 2)
        #expect(try plan.inputs(at: 1).tree("whole").outline == "[[5]]")
    }

    @Test func scalarAndListReadAnyTreeSlotAsItsItems() throws {
        let inputs = BroadcastPlan.make(inputs: ["whole": .tree(rows([4, 5], [6]))], specs: specs).inputs(at: 0)
        #expect(try inputs.list("whole").map(\.outlineText) == ["4", "5", "6"])
        #expect(try inputs.scalar("whole").outlineText == "4")
    }

    @Test func missingTreeInputThrowsANamedError() {
        let inputs = BroadcastPlan.make(inputs: [:], specs: specs).inputs(at: 0)
        #expect(throws: NodeError.missingInput("whole")) { try inputs.tree("whole") }
    }

    @Test func theTreeAccessNameIsSaved() throws {
        let spec = SocketSpec("whole", .any, access: .tree)
        let decoded = try JSONDecoder().decode(SocketSpec.self, from: JSONEncoder().encode(spec))
        #expect(decoded == spec)
        #expect(decoded.access == .tree)
    }
}

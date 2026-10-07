import Testing
@testable import CreatorGraph

struct BroadcastTests {
    let specs = [SocketSpec("a", .number), SocketSpec("b", .number), SocketSpec("all", .number, access: .list)]

    @Test func singleItemsRunOnceAndStaySingle() throws {
        let plan = BroadcastPlan.make(inputs: ["a": .one(.number(1)), "b": .one(.number(2))], specs: specs)
        #expect(plan.iterations == 1)
        #expect(plan.isSingle)
        #expect(try plan.inputs(at: 0).number("b") == 2)
    }

    @Test func longestListWinsAndShorterRepeatsItsLastItem() throws {
        let plan = BroadcastPlan.make(
            inputs: ["a": .list([.number(1), .number(2), .number(3)]), "b": .list([.number(10), .number(20)])],
            specs: specs
        )
        #expect(plan.iterations == 3)
        #expect(!plan.isSingle)
        #expect(try plan.inputs(at: 2).number("a") == 3)
        #expect(try plan.inputs(at: 2).number("b") == 20)
    }

    @Test func singleItemRepeatsAcrossAList() throws {
        let plan = BroadcastPlan.make(inputs: ["a": .list([.number(1), .number(2)]), "b": .one(.number(5))], specs: specs)
        #expect(try plan.inputs(at: 1).number("b") == 5)
    }

    @Test func emptyListProducesEmptyOutputs() {
        let plan = BroadcastPlan.make(inputs: ["a": .list([]), "b": .one(.number(5))], specs: specs)
        #expect(plan.iterations == 0)
        #expect(!plan.isSingle)
    }

    @Test func listAccessSocketsReceiveTheWholeListAndDoNotBroadcast() throws {
        let plan = BroadcastPlan.make(inputs: ["all": .list([.number(1), .number(2), .number(3)])], specs: specs)
        #expect(plan.iterations == 1)
        #expect(plan.isSingle)
        #expect(try plan.inputs(at: 0).list("all").count == 3)
    }

    @Test func missingInputThrowsANamedError() {
        let inputs = BroadcastPlan.make(inputs: [:], specs: specs).inputs(at: 0)
        #expect(throws: NodeError.missingInput("a")) { try inputs.number("a") }
    }

    @Test func wrongTypeThrowsTypeMismatch() {
        let inputs = BroadcastPlan.make(inputs: ["a": .one(.bool(true))], specs: specs).inputs(at: 0)
        #expect(throws: NodeError.typeMismatch("a", expected: .number)) { try inputs.number("a") }
    }
}

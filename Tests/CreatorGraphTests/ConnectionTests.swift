import Testing
@testable import CreatorGraph

struct ConnectionTests {
    @Test func compatibleTypesConnect() {
        let a = makeNode(IntegerNode.self), b = makeNode(AddNode.self)
        let g = graph([a, b])
        #expect(g.connectionProblem(from: Endpoint(node: a.id, socket: "value"), to: Endpoint(node: b.id, socket: "a"), registry: testRegistry) == nil)
    }

    @Test func incompatibleTypesAreRefused() {
        let box = makeNode(BoxNode.self), add = makeNode(AddNode.self)
        let g = graph([box, add])
        #expect(g.connectionProblem(from: Endpoint(node: box.id, socket: "solid"), to: Endpoint(node: add.id, socket: "a"), registry: testRegistry)
                == .typeMismatch(from: .solid, to: .number))
    }

    @Test func unknownSocketsAreRefused() {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        #expect(graph([a, b]).connectionProblem(from: Endpoint(node: a.id, socket: "nope"), to: Endpoint(node: b.id, socket: "a"), registry: testRegistry)
                == .unknownSocket("nope"))
    }

    @Test func selfLinksAndCyclesAreRefused() {
        let a = makeNode(AddNode.self), b = makeNode(AddNode.self)
        let g = graph([a, b], [link(a, "sum", b, "a")])
        #expect(g.connectionProblem(from: Endpoint(node: a.id, socket: "sum"), to: Endpoint(node: a.id, socket: "b"), registry: testRegistry) == .sameNode)
        #expect(g.connectionProblem(from: Endpoint(node: b.id, socket: "sum"), to: Endpoint(node: a.id, socket: "a"), registry: testRegistry) == .wouldCreateCycle)
    }

    @Test func evaluationOrderVisitsOnlyUpstreamOfDemand() {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self), unrelated = makeNode(ConstantNode.self)
        let g = graph([a, b, unrelated], [link(a, "value", b, "a")])
        let order = g.evaluationOrder(for: [b.id])
        #expect(order.order == [a.id, b.id])
        #expect(order.cyclic.isEmpty)
    }

    @Test func cyclesInLoadedGraphsAreReportedNotLooped() {
        let a = makeNode(AddNode.self), b = makeNode(AddNode.self)
        let g = graph([a, b], [link(a, "sum", b, "a"), link(b, "sum", a, "a")])
        #expect(g.evaluationOrder(for: [b.id]).cyclic == [a.id, b.id])
    }

    @Test func downstreamClosureFollowsLinks() {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self), c = makeNode(AddNode.self)
        let g = graph([a, b, c], [link(a, "value", b, "a"), link(b, "sum", c, "a")])
        #expect(g.downstreamClosure(of: [a.id]) == [a.id, b.id, c.id])
    }
}

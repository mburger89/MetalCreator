import Foundation
import Testing
import CreatorKernel
@testable import CreatorGraph

struct ConnectionTests {
    @Test func compatibleTypesConnect() {
        let a = makeNode(IntegerNode.self), b = makeNode(AddNode.self)
        let g = graph([a, b])
        #expect(g.connectionProblem(from: Endpoint(node: a.id, socket: "value"), to: Endpoint(node: b.id, socket: "a"),
                                       registry: testRegistry) == nil)
    }

    @Test func incompatibleTypesAreRefused() {
        let box = makeNode(BoxNode.self), add = makeNode(AddNode.self)
        let g = graph([box, add])
        #expect(g.connectionProblem(from: Endpoint(node: box.id, socket: "solid"), to: Endpoint(node: add.id, socket: "a"),
                                       registry: testRegistry)
                == .typeMismatch(from: .solid, to: .number))
    }

    @Test func unknownSocketsAreRefused() {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        #expect(graph([a, b]).connectionProblem(from: Endpoint(node: a.id, socket: "nope"), to: Endpoint(node: b.id, socket: "a"),
                                                registry: testRegistry)
                == .unknownSocket("nope"))
    }

    @Test func selfLinksAndCyclesAreRefused() {
        let a = makeNode(AddNode.self), b = makeNode(AddNode.self)
        let g = graph([a, b], [link(a, "sum", b, "a")])
        #expect(g.connectionProblem(from: Endpoint(node: a.id, socket: "sum"), to: Endpoint(node: a.id, socket: "b"),
                                       registry: testRegistry) == .sameNode)
        #expect(g.connectionProblem(from: Endpoint(node: b.id, socket: "sum"), to: Endpoint(node: a.id, socket: "a"),
                                       registry: testRegistry) == .wouldCreateCycle)
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

    @Test func cycleMembershipIsExactWhenACycleClosesThroughFinishedNodes() throws {
        func fixedNode(_ suffix: String) throws -> Node {
            let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(suffix)"))
            var node = makeNode(AddNode.self)
            node.id = NodeID(rawValue: uuid)
            return node
        }
        let a = try fixedNode("A"), b = try fixedNode("B"), c = try fixedNode("C"), d = try fixedNode("D")
        // A reads B; B reads C and D; D reads C; C reads A. C sorts before D.
        let g = graph([a, b, c, d], [
            link(b, "sum", a, "a"), link(c, "sum", b, "a"), link(d, "sum", b, "b"),
            link(c, "sum", d, "a"), link(a, "sum", c, "a"),
        ])
        let result = g.evaluationOrder(for: [a.id])
        #expect(result.cyclic == [a.id, b.id, c.id, d.id])
        #expect(result.order.count == 4)
        #expect(Set(result.order) == [a.id, b.id, c.id, d.id])
    }

    @Test func selfLinkedNodesAreCyclicAndDownstreamNodesAreNot() {
        let a = makeNode(AddNode.self), b = makeNode(AddNode.self)
        let g = graph([a, b], [link(a, "sum", a, "a"), link(a, "sum", b, "a")])
        #expect(g.evaluationOrder(for: [b.id]).cyclic == [a.id])
    }

    @Test func existingLinksDoNotBlockOtherInputsButTransitiveCyclesAreRefused() {
        let a = makeNode(AddNode.self), b = makeNode(AddNode.self), c = makeNode(AddNode.self)
        let g = graph([a, b, c], [link(a, "sum", b, "a"), link(b, "sum", c, "a")])
        #expect(g.connectionProblem(from: Endpoint(node: a.id, socket: "sum"), to: Endpoint(node: b.id, socket: "b"),
                                       registry: testRegistry) == nil)
        #expect(g.connectionProblem(from: Endpoint(node: c.id, socket: "sum"), to: Endpoint(node: a.id, socket: "a"),
                                       registry: testRegistry) == .wouldCreateCycle)
    }
}

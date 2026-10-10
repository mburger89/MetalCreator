import Testing
@testable import CreatorGraph

/// Wires reach a group node's sockets, and Group Input's and Group Output's, through the registry carrying the
/// document's definitions (groups spec §4).
struct GroupWiringTests {
    let doubler = Doubler()
    var registry: NodeRegistry { testRegistry.withGroups(table([doubler.definition])) }

    @Test func aWireReachesAGroupNodesInput() {
        let constant = makeNode(ConstantNode.self), group = instance(of: doubler.definition)
        let g = graph([constant, group])
        let from = Endpoint(node: constant.id, socket: "value"), to = Endpoint(node: group.id, socket: "value")
        #expect(g.connectionProblem(from: from, to: to, registry: registry) == nil)
        #expect(g.connectionProblem(from: from, to: to, registry: testRegistry) == .unknownSocket("value"))
    }

    @Test func aWireLeavesAGroupNodesOutput() {
        let group = instance(of: doubler.definition), add = makeNode(AddNode.self)
        let g = graph([group, add])
        let to = Endpoint(node: add.id, socket: "a")
        #expect(g.connectionProblem(from: Endpoint(node: group.id, socket: "result"), to: to, registry: registry) == nil)
        #expect(g.connectionProblem(from: Endpoint(node: group.id, socket: "nope"), to: to, registry: registry)
            == .unknownSocket("nope"))
    }

    @Test func insideTheBoundaryNodesWireLikeTheDefinitionsSockets() {
        let inside = doubler.definition.graph, box = makeNode(BoxNode.self)
        var withBox = inside
        withBox.nodes[box.id] = box
        let fromInput = Endpoint(node: doubler.input.id, socket: "value")
        #expect(inside.connectionProblem(from: fromInput, to: Endpoint(node: doubler.add.id, socket: "b"), registry: registry) == nil)
        let toOutput = Endpoint(node: doubler.output.id, socket: "result")
        #expect(inside.connectionProblem(from: Endpoint(node: doubler.add.id, socket: "sum"), to: toOutput, registry: registry) == nil)
        #expect(withBox.connectionProblem(from: Endpoint(node: box.id, socket: "solid"), to: toOutput, registry: registry)
            == .typeMismatch(from: .solid, to: .number))
    }
}

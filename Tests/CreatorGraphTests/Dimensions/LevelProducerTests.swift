import CreatorKernel
import Testing
@testable import CreatorGraph

/// A node that places instances (`placesInstances`), standing in for a pattern node.
private enum PlacerNode: NodeDefinition {
    static let typeID = "test.placer"
    static let displayName = "Placer"
    static let category = NodeCategory.value
    static let placesInstances = true
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

/// Which node of the level shown a face's tag names (DIM-3 Task 5).
@MainActor
struct LevelProducerTests {
    let registry = NodeRegistry([ConstantNode.self, AddNode.self, PlacerNode.self])

    @Test func aTopLevelNodeIsItsOwnProducer() {
        let a = makeNode(ConstantNode.self)
        let b = makeNode(AddNode.self)
        let content = GraphContent(graph: graph([a, b]))
        let producers = content.levelProducers(at: [], registry: registry)
        #expect(producers[a.id] == a.id)
        #expect(producers[b.id] == b.id)
        #expect(producers.count == 2)
    }

    @Test func aGroupsInsideMapsToTheGroupNode() throws {
        let doubler = Doubler()
        let node = instance(of: doubler.definition)
        let content = GraphContent(graph: graph([node]), definitions: table([doubler.definition]))
        let producers = content.levelProducers(at: [], registry: testRegistry)
        let inside = GroupScopes.inner(of: node, at: [], definitions: content.definitions)
        #expect(!inside.isEmpty)
        for identity in inside { #expect(producers[identity] == node.id) }
        #expect(producers[NodeID.scoped([node.id, doubler.add.id])] == node.id)
        #expect(producers[node.id] == node.id)
    }

    @Test func insideAGroupScopedIdentitiesMapToInnerNodes() {
        let doubler = Doubler()
        let node = instance(of: doubler.definition)
        let content = GraphContent(graph: graph([node]), definitions: table([doubler.definition]))
        let producers = content.levelProducers(at: [node.id], registry: testRegistry)
        #expect(producers[NodeID.scoped([node.id, doubler.add.id])] == doubler.add.id)
        #expect(producers[doubler.add.id] == nil, "the bare ID is the top level's name, not this level's")
        #expect(producers.count == doubler.definition.graph.nodes.count)
    }

    @Test func aPlacedCopyMapsToItsPlacer() {
        let hole = makeNode(PlacerNode.self)
        let place = makeNode(PlacerNode.self)
        let tool = makeNode(ConstantNode.self)
        let content = GraphContent(graph: graph([hole, place, tool]))
        let producers = content.levelProducers(at: [], registry: registry)
        #expect(producers[NodeID.instanceScoped([hole.id, hole.id])] == hole.id, "a hole pattern is its own tool")
        #expect(producers[NodeID.instanceScoped([place.id, tool.id])] == place.id)
        #expect(producers[NodeID.instanceScoped([tool.id, place.id])] == nil, "only a placer places")
        #expect(producers[tool.id] == tool.id)
    }
}

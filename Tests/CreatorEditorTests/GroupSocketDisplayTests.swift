import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// A group node is drawn, labelled and inspected with its definition's sockets (groups spec §4; the look is C2's).
@MainActor
struct GroupSocketDisplayTests {
    let definition = GroupDefinition.make(
        name: "Rib", inputs: [SocketSpec("height", .number, defaultValue: .number(10), unit: .millimetres)],
        outputs: [SocketSpec("solid", .solid)], registry: editorTestRegistry)
    var registry: NodeRegistry { editorTestRegistry.withGroups([definition.id: definition]) }

    func rib() -> (Node, Graph) {
        let node = registry.makeGroupNode(GroupNodes.groupTypeID, for: definition.id)
        var graph = Graph()
        graph.nodes[node.id] = node
        return (node, graph)
    }

    @Test func aGroupNodeDrawsItsDefinitionsSockets() {
        let (node, graph) = rib()
        let shape = NodeShape(node, in: graph, registry: registry)
        #expect(shape.title == "Rib")
        #expect(shape.inputs.map(\.name) == ["height"])
        #expect(shape.outputs.map(\.name) == ["solid"])
        #expect(shape.outputs.first?.type == .solid)
        let rows = NodeRowModel.rows(for: node, shape: shape, graph: graph, registry: registry)
        #expect(rows.first { $0.id == "in.height" }?.value == ValueText.format(10, unit: .millimetres))
    }

    @Test func theInspectorEditsAGroupNodesInputs() throws {
        let (node, graph) = rib()
        let page = InspectorBuilder.page(graph: graph, selection: [node.id], registry: registry, results: [:])
        let row = try #require(page.sections.first { $0.title == "Inputs" }?.rows.first)
        guard case .number(let field) = row else {
            Issue.record("expected a number row, got \(row)")
            return
        }
        #expect(field.socket == "height" && field.unit == .millimetres && field.value == .number(10))
    }
}

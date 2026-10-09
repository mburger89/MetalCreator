import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorEditor

/// Per-node sockets (`NodeDefinition.inputs(for:)`, the Sketch node's exposed dimensions; S4 → S5 handoff) are
/// drawn, labelled with their unit and default, and listed in the inspector, like declared ones.
@MainActor
struct PerNodeSocketTests {
    func perNodeNode() -> Node {
        testNode(PerNodeSocketTestNode.self, id: 1, at: .zero, values: ["extra": .text("width")],
                 registry: perNodeSocketTestRegistry)
    }

    @Test func aPerNodeSocketIsDrawnAfterTheDeclaredOnes() {
        let node = perNodeNode()
        var graph = Graph()
        graph.nodes[node.id] = node
        let shape = NodeShape(node, in: graph, registry: perNodeSocketTestRegistry)
        #expect(shape.inputs.map(\.name) == ["profile", "width"])
        #expect(shape.inputs.last?.type == .number)
    }

    @Test func itsRowShowsItsDefaultInItsUnit() {
        let node = perNodeNode()
        var graph = Graph()
        graph.nodes[node.id] = node
        let shape = NodeShape(node, in: graph, registry: perNodeSocketTestRegistry)
        let rows = NodeRowModel.rows(for: node, shape: shape, graph: graph, registry: perNodeSocketTestRegistry)
        #expect(rows.first { $0.id == "in.width" }?.value == ValueText.format(7, unit: .millimetres))
    }

    @Test func theFallbackInspectorListsItWithItsUnitAndDefault() throws {
        let node = perNodeNode()
        var graph = Graph()
        graph.nodes[node.id] = node
        let page = InspectorBuilder.page(graph: graph, selection: [node.id], registry: perNodeSocketTestRegistry, results: [:])
        let row = try #require(page.sections.first?.rows.first)
        guard case .number(let field) = row else {
            Issue.record("expected a number row, got \(row)")
            return
        }
        #expect(field.socket == "width" && field.unit == .millimetres && field.value == .number(7))
    }

    @Test func aSketchNodesExposedDimensionIsASocketOnTheCanvas() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(25, 0))
        let dimension = sketch.addDimension(.length(line), value: 25)
        sketch.dimensions[dimension]?.isExposed = true
        var node = BuiltInNodes.registry.makeNode(SketchNode.typeID)
        node.inputValues[NodeSetting.sketch] = .sketch(sketch)
        var graph = Graph()
        graph.nodes[node.id] = node
        let shape = NodeShape(node, in: graph, registry: BuiltInNodes.registry)
        #expect(shape.inputs.map(\.name) == ["plane", "references", "d1"])
        let rows = NodeRowModel.rows(for: node, shape: shape, graph: graph, registry: BuiltInNodes.registry)
        #expect(rows.first { $0.id == "in.d1" }?.value == ValueText.format(25, unit: .millimetres))
    }

    /// The Sketch node declares an inspector ("Edit sketch"), which can't name its exposed dimensions, so they follow
    /// it as number rows: outside sketch mode the inspector still edits them.
    @Test func aSketchNodesInspectorHasEditSketchAndItsExposedDimensions() throws {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(25, 0))
        let dimension = sketch.addDimension(.length(line), value: 25)
        sketch.dimensions[dimension]?.isExposed = true
        var node = BuiltInNodes.registry.makeNode(SketchNode.typeID)
        node.inputValues[NodeSetting.sketch] = .sketch(sketch)
        var graph = Graph()
        graph.nodes[node.id] = node
        let page = InspectorBuilder.page(graph: graph, selection: [node.id], registry: BuiltInNodes.registry, results: [:])
        let rows = page.sections.flatMap(\.rows)
        #expect(rows.contains { if case .button(_, .editSketch) = $0 { true } else { false } })
        let field = try #require(rows.lazy.compactMap { row -> InputField? in
            if case .number(let field) = row { field } else { nil }
        }.first)
        #expect(field.socket == "d1" && field.unit == .millimetres && field.value == .number(25))
    }
}

import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// A canvas row shows a choice by the option's name (display finding 3), as the inspector's segmented control does.
@MainActor
struct NodeRowChoiceTests {
    func values(of type: any NodeDefinition.Type, _ settings: [SocketName: ConstantValue] = [:]) -> [String: String?] {
        var node = BuiltInNodes.registry.makeNode(type.typeID)
        for (name, value) in settings { node.inputValues[name] = value }
        var graph = Graph()
        graph.nodes[node.id] = node
        let shape = NodeShape(node, in: graph, registry: BuiltInNodes.registry)
        let rows = NodeRowModel.rows(for: node, shape: shape, graph: graph, registry: BuiltInNodes.registry)
        return Dictionary(rows.map { ($0.label, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    @Test func holePatternShowsItsStyleByName() {
        #expect(values(of: HolePatternNode.self)["Style"] == "Plain")
        #expect(values(of: HolePatternNode.self, ["style": .integer(1)])["Style"] == "Counterbore")
    }

    @Test func extrudeShowsItsModeByName() {
        #expect(values(of: ExtrudeNode.self)["Mode"] == "One side")
        #expect(values(of: ExtrudeNode.self, ["mode": .integer(1)])["Mode"] == "Symmetric")
    }

    /// An index outside the options, or a plain integer input, still shows its number.
    @Test func otherIntegersKeepTheirNumbers() {
        #expect(values(of: ExtrudeNode.self, ["mode": .integer(7)])["Mode"] == "7")
        #expect(values(of: PartitionNode.self)["Size"] == "2")
    }
}

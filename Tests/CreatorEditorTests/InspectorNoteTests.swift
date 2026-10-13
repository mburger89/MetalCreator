import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// A node's `.note` control (fields spec §4: Field Scatter's help) is a read-only line of text in the inspector.
@MainActor
struct InspectorNoteTests {
    @Test func aNoteControlHasNoSocketAndBecomesARecipeRow() {
        #expect(InspectorControl.note("Hello").socket == nil)
        let node = BuiltInNodes.registry.makeNode(FieldScatterNode.typeID)
        let page = InspectorBuilder.page(graph: Graph(nodes: [node.id: node], links: []), selection: [node.id],
                                         registry: BuiltInNodes.registry, results: [:])
        let note = page.sections.first { $0.title == "Note" }
        #expect(note?.rows == [.recipe(label: "Note", text: FieldScatterNode.help)])
    }

    @Test func fieldScatterShowsItsSpacingDensityAndSeedControls() {
        let node = BuiltInNodes.registry.makeNode(FieldScatterNode.typeID)
        let page = InspectorBuilder.page(graph: Graph(nodes: [node.id: node], links: []), selection: [node.id],
                                         registry: BuiltInNodes.registry, results: [:])
        #expect(page.sections.map(\.title) == ["Spacing", "Density", "Random", "Note"])
        #expect(page.header?.title == "Field Scatter")
    }
}

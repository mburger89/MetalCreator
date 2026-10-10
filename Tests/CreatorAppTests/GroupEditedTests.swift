import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// An edit that changes only a group definition marks the document edited (groups spec §5): New and Open ask before
/// throwing it away, and the title says "— Edited".
@MainActor
struct GroupEditedTests {
    @Test func editsToADefinitionMarkTheDocumentEditedUntilSaved() async throws {
        let registry = BuiltInNodes.registry
        var rib = GroupDefinition.make(name: "Rib", registry: registry)
        let rectangle = registry.makeNode(RectangleNode.typeID)
        rib.graph.nodes[rectangle.id] = rectangle
        let node = registry.withGroups([rib.id: rib]).makeGroupNode(GroupNodes.groupTypeID, for: rib.id)
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: Graph(nodes: [node.id: node]), definitions: [rib.id: rib]))
        await app.settle()
        #expect(!app.isEdited, "opening a file with definitions isn't an edit")
        let url = temporaryURL("rib.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }

        try app.document.perform(.setInput(rectangle.id, "width", .number(5)), at: .definition(rib.id))
        #expect(app.isEdited, "an edit inside a definition")
        try app.save(to: url)
        #expect(!app.isEdited)

        var interface = rib.interface
        interface.accent = .green
        try app.document.perform(.setInterface(rib.id, interface))
        #expect(app.isEdited, "a new accent")
        try app.save(to: url)
        #expect(!app.isEdited)
        app.document.undo()
        #expect(app.isEdited, "undoing past the save")
    }
}

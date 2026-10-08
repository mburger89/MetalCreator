import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// The real M3 node definitions through the editor's inspector and node-shape builders. Every
/// other editor test uses hand-written fixtures; this one catches a declaration the editor
/// can't draw before M6 wires `BuiltInNodes.registry` into the app. `CreatorNodes` is a
/// test-only dependency (the library stays free of it, spec Errata (M5)).
@MainActor
struct BuiltInNodesInspectorTests {
    @Test(arguments: BuiltInNodes.all.map { $0.typeID })
    func everyBuiltInNodeBuildsADrawableInspectorPage(typeID: String) throws {
        let registry = BuiltInNodes.registry
        let definition = try #require(registry[typeID])
        let node = registry.makeNode(typeID)
        let graph = Graph(nodes: [node.id: node], links: [], parameters: [])
        let page = InspectorBuilder.page(graph: graph, selection: [node.id], registry: registry, results: [:])

        #expect(page.header?.title == definition.displayName)
        // A control the builder can't bind draws as an empty read-only row.
        for section in page.sections {
            #expect(!section.rows.contains(.readOnly(label: "", text: "")), "\(typeID): unbound row in \(section.title)")
        }
        // `InspectorPanel` identifies sections by title.
        let titles = page.sections.map(\.title)
        #expect(Set(titles).count == titles.count, "\(typeID): duplicate section titles \(titles)")

        let inputs = Set(definition.inputs.map(\.name))
        let outputs = Set(definition.outputs.map(\.name))
        for control in definition.inspector.flatMap(\.controls) {
            guard let socket = control.socket else { continue }
            var allowed = inputs.union(NodeSetting.all)
            if case .ruleSummary = control { allowed.formUnion(outputs) }
            #expect(allowed.contains(socket), "\(typeID): control names unknown socket \(socket)")
        }

        let shape = NodeShape(node, in: graph, registry: registry)
        #expect(!shape.isMissing)
        #expect(shape.inputs.map(\.name) == definition.inputs.map(\.name))
        #expect(shape.outputs.map(\.name) == definition.outputs.map(\.name))
    }
}

import Testing
@testable import CreatorGraph

struct RegistryTests {
    @Test func looksUpDefinitionsByTypeID() throws {
        let definition = try #require(testRegistry["test.add"])
        #expect(definition.displayName == "Add")
        #expect(testRegistry["missing.type"] == nil)
    }

    @Test func makeNodeUsesDefinitionMetadata() {
        let node = testRegistry.makeNode(VersionedNode.typeID, at: .init(4, 5))
        #expect(node.typeVersion == 2)
        #expect(node.name == "Versioned")
        #expect(node.position == .init(4, 5))
    }

    @Test func defaultsAreEmptyInspectorAndNoHandles() {
        #expect(AddNode.inspector.isEmpty)
        #expect(AddNode.handles.isEmpty)
        #expect(AddNode.readsParameters == false)
    }
}

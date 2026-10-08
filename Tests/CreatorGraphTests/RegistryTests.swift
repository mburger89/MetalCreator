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

    @Test func outputCategoryNodesAreCreatedAsOutputs() {
        #expect(testRegistry.makeNode(SinkNode.typeID).isOutput)
        #expect(!testRegistry.makeNode(AddNode.typeID).isOutput)
        #expect(!testRegistry.makeNode("missing.type").isOutput)
    }

    @Test func makeNodeSeedsDefaultSettings() {
        #expect(testRegistry.makeNode(SinkNode.typeID).inputValues == [NodeSetting.showHandle: .bool(true)])
        #expect(testRegistry.makeNode(AddNode.typeID).inputValues.isEmpty)
    }

    @Test func parameterSettingsRoundTrip() {
        let id = ParameterID()
        #expect(ConstantValue.parameter(id).parameterID == id)
        #expect(ConstantValue.text("garbage").parameterID == nil)
        #expect(ConstantValue.number(1).parameterID == nil)
    }

    @Test func defaultsAreEmptyInspectorAndNoHandles() {
        #expect(AddNode.inspector.isEmpty)
        #expect(AddNode.handles.isEmpty)
        #expect(AddNode.readsParameters == false)
        #expect(AddNode.defaultSettings.isEmpty)
    }
}

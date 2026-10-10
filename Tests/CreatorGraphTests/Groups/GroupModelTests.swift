import Foundation
import Testing
@testable import CreatorGraph

struct GroupModelTests {
    @Test func everyRegistryMakesGroupNodesButThePaletteDoesNotListThem() throws {
        for typeID in [GroupNodes.groupTypeID, GroupNodes.inputTypeID, GroupNodes.outputTypeID] {
            #expect(testRegistry[typeID] != nil)
            #expect(testRegistry.makeNode(typeID).typeID == typeID)
        }
        #expect(testRegistry.makeNode(GroupNodes.groupTypeID).name == "Group")
        #expect(!testRegistry.all.contains { GroupNodes.typeIDs.contains($0.typeID) })
        #expect(testRegistry.all.count == 18)
    }

    @Test func aGroupNodesSocketsAreItsDefinitions() {
        let doubler = Doubler()
        let registry = testRegistry.withGroups(table([doubler.definition]))
        let node = instance(of: doubler.definition)
        #expect(node.name == "Doubler")
        #expect(node.inputValues[NodeSetting.group] == .group(doubler.id))
        #expect(registry.inputs(for: node) == doubler.definition.inputs)
        #expect(registry.outputs(for: node) == doubler.definition.outputs)
        #expect(registry.outputs(for: doubler.input) == doubler.definition.inputs)
        #expect(registry.inputs(for: doubler.input).isEmpty)
        #expect(registry.inputs(for: doubler.output).map(\.name) == ["result"])
        #expect(registry.inputs(for: doubler.output).allSatisfy { $0.isOptional })
        #expect(registry.outputs(for: doubler.output).isEmpty)
        // A registry without the document's definitions knows the type but not the sockets.
        #expect(testRegistry.inputs(for: node).isEmpty)
    }

    @Test func otherNodesKeepTheirTypesSockets() {
        let extra = makeNode(ExtraInputsNode.self, ["extra": .text("w,h")])
        #expect(testRegistry.inputs(for: extra).map(\.name) == ["value", "w", "h"])
        #expect(testRegistry.outputs(for: makeNode(AddNode.self)) == AddNode.outputs)
        #expect(testRegistry.inputs(for: Node(typeID: "missing.type", name: "Missing")).isEmpty)
    }

    @Test func aNewDefinitionHoldsOnlyItsBoundary() throws {
        let definition = GroupDefinition.make(name: "Rib", registry: testRegistry)
        #expect(definition.graph.nodes.count == 2)
        let input = try #require(definition.inputNode), output = try #require(definition.outputNode)
        #expect(input.inputValues[NodeSetting.group] == .group(definition.id))
        #expect(output.inputValues[NodeSetting.group] == .group(definition.id))
        #expect(input.position == GroupDefinition.defaultInputPosition)
        #expect(output.position == GroupDefinition.defaultOutputPosition)
        #expect(definition.accent == .purple)
    }

    @Test func theGroupSettingNamesADefinition() {
        let id = GroupID()
        #expect(ConstantValue.group(id).groupID == id)
        #expect(ConstantValue.text("garbage").groupID == nil)
        #expect(NodeSetting.all.contains(NodeSetting.group))
    }

    @Test func socketsRoundTripThroughJSON() throws {
        let specs = [
            SocketSpec("height", .number, defaultValue: .number(10), unit: .millimetres, range: 1...50),
            SocketSpec("tools", .solid, access: .list, optional: true),
        ]
        #expect(try JSONDecoder().decode([SocketSpec].self, from: JSONEncoder().encode(specs)) == specs)
        let minimal = try JSONDecoder().decode(SocketSpec.self, from: Data(#"{"name": "a", "type": "integer"}"#.utf8))
        #expect(minimal == SocketSpec("a", .integer))
    }

    @Test func aDefinitionRoundTripsThroughJSON() throws {
        var definition = Doubler().definition
        definition.accent = .cyan
        #expect(try JSONDecoder().decode(GroupDefinition.self, from: JSONEncoder().encode(definition)) == definition)
    }

    @Test func anUnknownAccentReadsAsPurple() throws {
        let json = #"{"id": "\#(UUID().uuidString)", "name": "Rib", "accent": "chartreuse"}"#
        let definition = try JSONDecoder().decode(GroupDefinition.self, from: Data(json.utf8))
        #expect(definition.accent == .purple)
        #expect(definition.graph == Graph())
    }

    @Test func theInterfaceIsNameAccentAndSockets() {
        var definition = Doubler().definition
        let interface = GroupInterface(name: "Twice", accent: .green, inputs: [], outputs: [SocketSpec("out", .number)])
        definition.interface = interface
        #expect(definition.interface == interface)
        #expect(definition.name == "Twice")
        #expect(definition.graph.nodes.count == 3)
    }
}

import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// Fields are never saved, so under format 6 no group interface may carry one: a `"type": "field"` socket in a format-6 file is a
/// file an older build cannot decode, and CLAUDE.md bumps the format for that, which is 7b-2's job. A field chain kept wholly
/// inside a group is fine. (The helper nodes are `FieldValueTests`'.)
@MainActor
struct GroupFieldTests {
    static let registry = NodeRegistry([FieldSourceNode.self, FieldSinkNode.self, NumberSourceNode.self])
    static let refusal = GraphError.invalidValue(
        "A field can't cross a group's edge yet: group the nodes on both sides of the wire together, "
            + "or sample the field into numbers first.")

    let number = Self.registry.makeNode(NumberSourceNode.typeID)
    let source = Self.registry.makeNode(FieldSourceNode.typeID)
    let sink = Self.registry.makeNode(FieldSinkNode.typeID)
    let after = Self.registry.makeNode(FieldSinkNode.typeID)

    func link(_ from: Node, _ socket: SocketName, _ to: Node, _ target: SocketName) -> Link {
        Link(from: Endpoint(node: from.id, socket: socket), to: Endpoint(node: to.id, socket: target))
    }

    /// number → source → sink → after: a number, then a field made from it, passed on twice.
    func document() -> DocumentModel {
        let nodes = [number, source, sink, after]
        var graph = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: [
            link(number, "value", source, "value"), link(source, "field", sink, "field"), link(sink, "field", after, "field"),
        ])
        graph.sortLinks()
        return DocumentModel(file: GraphFile(graph: graph), registry: Self.registry, kernel: FakeKernel())
    }

    func group(_ ids: Set<NodeID>, in document: DocumentModel) throws {
        let edit = try GroupCommands.group(ids, in: .root, of: document.content, registry: Self.registry)
        try document.perform(edit.command)
    }

    @Test func aFieldWireCrossingTheEdgeIsRefusedEitherWay() {
        // Each selection has a field wire into the group, out of it, or both.
        let selections: [Set<NodeID>] = [[sink.id], [source.id], [after.id], [source.id, sink.id], [sink.id, after.id]]
        for ids in selections {
            let document = document()
            let before = document.content
            #expect(throws: Self.refusal) { try group(ids, in: document) }
            #expect(document.content == before, "a refused Group changes nothing")
        }
    }

    @Test func anInterfaceSocketOfTypeFieldIsRefused() throws {
        let document = document()
        try group([source.id, sink.id, after.id], in: document)
        let definition = try #require(document.definitions.values.first)
        var wider = definition.interface
        wider.outputs.append(SocketSpec("size", .field))
        #expect(throws: Self.refusal) { try document.perform(.setInterface(definition.id, wider)) }
        var wideInput = definition.interface
        wideInput.inputs.append(SocketSpec("size", .field, defaultValue: .number(1)))
        #expect(throws: Self.refusal) { try document.perform(.setInterface(definition.id, wideInput)) }
        #expect(document.definitions[definition.id]?.interface == definition.interface, "nothing changed")
    }

    @Test func nodesThatKeepTheFieldWireInsideGroupEvaluateAndSaveAsFormatSix() async throws {
        let document = document()
        try group([source.id, sink.id, after.id], in: document)
        let definition = try #require(document.definitions.values.first)
        #expect(definition.inputs.map(\.name) == ["value"], "the number comes in; no field crosses")
        #expect(definition.outputs.isEmpty)
        let node = try #require(document.graph.nodes.values.first { $0.typeID == GroupNodes.groupTypeID })
        // The group node is evaluated only to show its inside: the field is made, passed on and described inside it.
        let report = try await Evaluator(registry: Self.registry, kernel: FakeKernel())
            .evaluate(document.graph, definitions: document.definitions, demand: [], inspecting: [node.id])
        let inside = report.innerResults[[node.id, after.id]]?.outputs?["field"]
        guard case .one(.field(let field))? = inside else {
            Issue.record("expected a field inside the group, got \(String(describing: inside))")
            return
        }
        #expect(field.description == "4.5 × 3")
        let file = GraphFile(graph: document.graph, definitions: document.definitions)
        #expect(file.formatVersion == 6)
        #expect(try GraphFileIO.decode(try GraphFileIO.encode(file), registry: Self.registry) == file)
    }
}

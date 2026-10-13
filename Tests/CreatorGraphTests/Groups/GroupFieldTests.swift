import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// A field may cross a group's edge (file format 7, fields spec §5). Under format 6 it could not: `"field"` is no socket type a
/// format-6 reader decodes, so 7b-1 refused it; 7b-2's format 7 lifts that. (The helper nodes are `FieldValueTests`'.)
@MainActor
struct GroupFieldTests {
    static let registry = NodeRegistry([FieldSourceNode.self, FieldSinkNode.self, NumberSourceNode.self])

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

    /// The recipe of the field `after` outputs, found from the top level.
    func recipe(of document: DocumentModel) async throws -> String? {
        let report = try await Evaluator(registry: Self.registry, kernel: FakeKernel())
            .evaluate(document.graph, definitions: document.definitions, demand: [after.id])
        guard case .one(.field(let field))? = report.results[after.id]?.outputs?["field"] else { return nil }
        return field.description
    }

    @Test func aFieldWireCrossingTheEdgeIsAcceptedInEitherDirectionAndTheFieldArrivesUnchanged() async throws {
        let plain = try await recipe(of: document())
        #expect(plain == "4.5 × 3")
        // Each selection leaves `after` outside, with a field wire into the group, out of it, or both.
        let selections: [Set<NodeID>] = [[sink.id], [source.id], [source.id, sink.id]]
        for ids in selections {
            let document = document()
            try group(ids, in: document)
            let definition = try #require(document.definitions.values.first)
            #expect((definition.inputs + definition.outputs).contains { $0.type == .field }, "a field socket on the group's edge")
            #expect(try await recipe(of: document) == plain, "the group changes nothing about the field")
        }
    }

    @Test func aGroupWhoseFieldNeverLeavesItStillGroups() throws {
        let document = document()
        try group([sink.id, after.id], in: document)
        let definition = try #require(document.definitions.values.first)
        #expect(definition.inputs.map(\.type) == [.field] && definition.outputs.isEmpty)
    }

    @Test func anInterfaceSocketOfTypeFieldIsAccepted() throws {
        let document = document()
        try group([source.id, sink.id, after.id], in: document)
        let definition = try #require(document.definitions.values.first)
        var wider = definition.interface
        wider.outputs.append(SocketSpec("size", .field))
        wider.inputs.append(SocketSpec("scale", .field, defaultValue: .number(1)))
        try document.perform(.setInterface(definition.id, wider))
        #expect(document.definitions[definition.id]?.interface == wider)
    }

    @Test func aGroupWithFieldSocketsSavesAsFormatSevenAndReopensEqual() async throws {
        let document = document()
        try group([sink.id], in: document)
        let data = try document.fileData()
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.contains("\"formatVersion\" : 7") && text.contains("\"type\" : \"field\""))
        let reopened = try GraphFileIO.decode(data, registry: Self.registry)
        #expect(reopened.definitions == document.definitions && reopened.graph == document.graph)
        let again = DocumentModel(file: reopened, registry: Self.registry, kernel: FakeKernel())
        #expect(try await recipe(of: again) == "4.5 × 3")
    }

    @Test func undoingTheGroupPutsTheFieldWireBack() throws {
        let document = document()
        let before = document.content
        try group([sink.id], in: document)
        document.undo()
        #expect(document.content == before)
    }
}

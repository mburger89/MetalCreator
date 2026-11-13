import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Synchronization
import Testing
@testable import CreatorApp
@testable import CreatorEditor
@testable import CreatorMCP

/// The AI server's view of the open document: the rules about when an edit may run, and the files.
@MainActor
@Suite(.timeLimit(.minutes(20)))
struct AppDocumentSessionTests {
    func rig(_ graph: Graph = Graph()) async -> (AppModel, AppDocumentSession, MCPServerCore) {
        let app = await makeApp(graph)
        let session = AppDocumentSession(model: app)
        let core = MCPServerCore(session: session, tools: MCPCatalogue.tools, resources: MCPCatalogue.resources, serverVersion: "test")
        return (app, session, core)
    }

    func call(_ core: MCPServerCore, _ tool: String, _ arguments: JSONValue = .object([:])) async throws
        -> (result: JSONValue, isError: Bool) {
        let request = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .int(1), "method": .string("tools/call"),
            "params": .object(["name": .string(tool), "arguments": arguments]),
        ])
        let sent = Sent()
        await core.handle(line: request.encoded()) { sent.add($0) }
        let reply = try JSONValue.parse(try #require(sent.all.last))
        let result = try #require(reply["result"])
        let text = try #require(result["content"]?.array?.first?["text"]?.string)
        let isError = result["isError"]?.bool ?? false
        return (isError ? .string(text) : try JSONValue.parse(Data(text.utf8)), isError)
    }

    private func addBox(_ core: MCPServerCore) async throws -> (result: JSONValue, isError: Bool) {
        try await call(core, "add_node", .object(["type": .string("creator.rectangle")]))
    }

    @Test func refusesWhileSketching() async throws {
        let (sketch, _) = AppUnitsTests().lineSketch()
        var builder = GraphBuilder()
        let box = builder.sketchedBox(sketch)
        let (app, session, core) = await rig(builder.graph)
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        let (result, isError) = try await addBox(core)
        #expect(isError)
        #expect(result.string == "MetalCreator is editing a sketch. Click Finish in the sketch toolbar, then try again.")
        #expect(session.editRefusal() != nil)
        let read = try await call(core, "get_document")
        #expect(!read.isError)
    }

    @Test func refusesWhileAnAlertIsUp() async throws {
        let (app, _, core) = await rig()
        app.alert = .problem(AppProblem("Something failed", "It did."))
        let (result, isError) = try await addBox(core)
        #expect(isError)
        #expect(result.string == "MetalCreator is asking you something. Answer it, then try again.")
    }

    @Test func commitsPendingEntryBeforeEditing() async throws {
        var builder = GraphBuilder()
        let box = builder.box().rectangle
        let (app, _, core) = await rig(builder.graph)
        var committed = false
        app.editor.notePendingEntry(PendingEntry(text: "typed", textCommit: { [app] _ in
            committed = true
            try? app.document.perform(.move(box.id, to: Vector2(5, 5)), name: UndoName.move)
        }))
        let (_, isError) = try await addBox(core)
        #expect(!isError)
        #expect(committed)
        #expect(app.document.graph.nodes[box.id]?.position == Vector2(5, 5))
        #expect(app.document.undoName == "Add Rectangle", "the client's step is its own, after the person's")
    }

    @Test func sessionFollowsReplacedDocument() async throws {
        let (app, _, core) = await rig()
        _ = try await addBox(core)
        let id = try #require(app.document.graph.nodes.keys.first).rawValue.uuidString
        app.startNewDocument()
        await app.settle()
        let document = try await call(core, "get_document")
        #expect(document.result["nodes"]?.array?.isEmpty == true)
        let old = try await call(core, "get_node", .object(["node": .string(id)]))
        #expect(old.isError)
    }

    @Test func newRefusesUnsavedWithoutDiscard() async throws {
        let (app, _, core) = await rig()
        _ = try await addBox(core)
        #expect(app.isEdited)
        let refused = try await call(core, "new_document")
        #expect(refused.isError)
        #expect(refused.result.string == "The document has unsaved changes. Save it first, or pass discard_unsaved.")
        let done = try await call(core, "new_document", .object(["discard_unsaved": .bool(true)]))
        #expect(!done.isError)
        #expect(app.document.graph.nodes.isEmpty)
    }

    @Test func saveNeedsAPathUntilSavedAndRefusesAnotherFileWithoutOverwrite() async throws {
        let (app, _, core) = await rig()
        let never = try await call(core, "save_document")
        #expect(never.result.string == "The document has never been saved; give a path.")
        let url = temporaryURL("mcp-save.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("x".utf8).write(to: url)
        let exists = try await call(core, "save_document", .object(["path": .string(url.path)]))
        #expect(exists.isError)
        #expect(exists.result.string == "\(url.lastPathComponent) already exists. Pass overwrite to replace it.")
        let replaced = try await call(core, "save_document", .object(["path": .string(url.path), "overwrite": .bool(true)]))
        #expect(!replaced.isError)
        #expect(app.fileURL == url)
        let again = try await call(core, "save_document")
        #expect(!again.isError, "the document's own file needs no overwrite")
    }

    /// FakeKernel has no STL or STEP writer, so this exports 3MF, which the app streams itself.
    @Test func exportWritesTheFile() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let (_, _, core) = await rig(builder.graph)
        let url = temporaryURL("mcp-export.3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await call(core, "export", .object(["kind": .string("3mf"), "path": .string(url.path)]))
        #expect(!result.isError)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let again = try await call(core, "export", .object(["kind": .string("3mf"), "path": .string(url.path)]))
        #expect(again.isError, "an existing file is not replaced without overwrite")
    }

    @Test func setFileLinksAnImage() async throws {
        var builder = GraphBuilder()
        let field = builder.add(ImageFieldNode.self)
        let (app, _, core) = await rig(builder.graph)
        let url = temporaryURL("mcp-image.png")
        defer { try? FileManager.default.removeItem(at: url) }
        try AppTestImages.png().write(to: url)
        let result = try await call(core, "set_file", .object(["node": .string(field.id.rawValue.uuidString), "path": .string(url.path)]))
        #expect(!result.isError)
        guard case .image(let reference)? = app.document.graph.nodes[field.id]?.inputValues[NodeSetting.image] else {
            Issue.record("no image setting")
            return
        }
        #expect(!reference.isEmbedded)
        #expect(app.document.undoName == "Link Image")
        let undone = try await call(core, "undo")
        #expect(!undone.isError, "a file setting is the client's own step")
    }

    // MARK: Refusals

    /// A sample of every family of client edit: adding, setting, wiring, undoing, a file setting and a file save.
    private func samples(_ parts: (rectangle: Node, extrude: Node, output: Node)) -> [(String, JSONValue)] {
        let id = JSONValue.string(parts.extrude.id.rawValue.uuidString)
        let rectangle = parts.rectangle.id.rawValue.uuidString
        let extrude = parts.extrude.id.rawValue.uuidString
        return [
            ("add_node", .object(["type": .string("creator.rectangle")])),
            ("set_inputs", .object(["node": id, "values": .object(["distance": .number(5)])])),
            ("connect", .object(["from": .string("\(rectangle).profile"), "to": .string("\(extrude).profile")])),
            ("undo", .object([:])),
            ("set_file", .object(["node": id, "path": .string(absoluteTestPath("none.png"))])),
            ("save_document", .object(["path": .string(absoluteTestPath("mcp-refused.mcgraph"))])),
        ]
    }

    private func expectRefused(
        _ core: MCPServerCore, _ sentence: String, parts: (rectangle: Node, extrude: Node, output: Node)
    ) async throws {
        for (tool, arguments) in samples(parts) {
            let outcome = try await call(core, tool, arguments)
            #expect(outcome.isError && outcome.result.string == sentence, "\(tool): isError \(outcome.isError), result \(outcome.result)")
        }
        #expect(!FileManager.default.fileExists(atPath: absoluteTestPath("mcp-refused.mcgraph")))
    }

    @Test func sketchModeRefusesEveryEditFamily() async throws {
        let (sketch, _) = AppUnitsTests().lineSketch()
        var builder = GraphBuilder()
        let box = builder.sketchedBox(sketch)
        let extra = builder.box()
        let (app, _, core) = await rig(builder.graph)
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        try await expectRefused(core, "MetalCreator is editing a sketch. Click Finish in the sketch toolbar, then try again.", parts: extra)
    }

    @Test func aPickInProgressRefuses() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let (app, _, core) = await rig(builder.graph)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        let solid = try #require(app.viewport.items.first?.solid)
        let source = try #require(app.producer(of: solid))
        app.pick = PickSession(solid: solid, source: source, rule: nil, consumer: nil, picked: [])
        try await expectRefused(core, "MetalCreator is waiting for a pick in the view. Finish or cancel it, then try again.",
                                parts: box)
    }

    @Test func aModelDimensionInProgressRefuses() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let (app, _, core) = await rig(builder.graph)
        #expect(app.beginModelDimension())
        try await expectRefused(core, "MetalCreator is adding a dimension. Finish or cancel it, then try again.", parts: box)
    }

    @Test func scrubbingRefuses() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let (app, _, core) = await rig(builder.graph)
        app.document.isScrubbing = true
        try await expectRefused(core, "The person is changing a value; try again in a moment.", parts: box)
        app.document.isScrubbing = false
    }

    @Test func aCanvasDragRefuses() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let (app, _, core) = await rig(builder.graph)
        app.editor.setInteraction(.moving(start: SelectionPositions(), key: "drag"))
        try await expectRefused(core, "The person is moving something on the canvas; try again in a moment.", parts: box)
        app.editor.setInteraction(nil)
        let after = try await addBox(core)
        #expect(!after.isError)
    }

    @Test func aTypedValueNotYetCommittedCountsAsUnsavedWork() async throws {
        var builder = GraphBuilder()
        let box = builder.box().rectangle
        let (app, _, core) = await rig(builder.graph)
        app.editor.notePendingEntry(PendingEntry(text: "typed", textCommit: { [app] _ in
            try? app.document.perform(.move(box.id, to: Vector2(7, 7)), name: UndoName.move)
        }))
        let refused = try await call(core, "new_document")
        #expect(refused.isError)
        #expect(refused.result.string == "The document has unsaved changes. Save it first, or pass discard_unsaved.")
        #expect(app.document.graph.nodes[box.id]?.position == Vector2(7, 7))
    }

    @Test func setFileAddressesTheTopLevelFromInsideAGroup() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let field = builder.add(ImageFieldNode.self)
        let (app, _, core) = await rig(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        #expect(app.editor.isInsideGroup)
        let url = temporaryURL("mcp-group-image.png")
        defer { try? FileManager.default.removeItem(at: url) }
        try AppTestImages.png().write(to: url)
        let result = try await call(core, "set_file", .object(["node": .string(field.id.rawValue.uuidString), "path": .string(url.path)]))
        #expect(!result.isError)
        guard case .image(let reference)? = app.document.graph.nodes[field.id]?.inputValues[NodeSetting.image] else {
            Issue.record("no image setting on the top-level node")
            return
        }
        #expect(!reference.isEmbedded)
    }
}

final class Sent: Sendable {
    private let lines = Mutex<[Data]>([])
    func add(_ data: Data) { lines.withLock { $0.append(data) } }
    var all: [Data] { lines.withLock { $0 } }
}

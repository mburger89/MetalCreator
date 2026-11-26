import CreatorDrawing
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Synchronization
import Testing
@testable import CreatorApp
@testable import CreatorMCP

/// The AI server's drawing tools over the app (DR-5 R19): reads in every mode, exports refused whenever edits are, one wait.
@MainActor
struct MCPDrawingTests {
    func rig(_ app: AppModel) -> (AppDocumentSession, MCPServerCore) {
        let session = AppDocumentSession(model: app)
        let core = MCPServerCore(session: session, tools: MCPCatalogue.tools, resources: MCPCatalogue.resources, serverVersion: "test")
        return (session, core)
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

    /// Replaces what the dimension is attached to with a name no edge has, so it is lost whenever it is judged.
    func lose(_ id: AnnotationID, in app: AppModel) throws {
        var drawings = app.drawing.editor.document
        let nothing = EdgePick(
            key: EdgeKey([TopoTag(node: NodeID(), item: 0, role: .startCap)], [TopoTag(node: NodeID(), item: 0, role: .endCap)]),
            matchCount: 1)
        guard let index = drawings.sheets.firstIndex(where: { $0.annotation(id) != nil }),
            var annotation = drawings.sheets[index].annotation(id), case .dimension(var dimension) = annotation.kind
        else {
            Issue.record("no dimension")
            return
        }
        dimension.anchors = [.edge(nothing)]
        annotation.kind = .dimension(dimension)
        drawings.sheets[index].setAnnotation(annotation)
        try app.document.perform(.setDrawings(drawings), name: "Lose")
    }

    /// An app with one sheet, one base view and one dimension on it.
    func dimensioned(kernel: any Kernel = FakeKernel()) async throws -> (AppModel, ViewID, AnnotationID) {
        let app = await AppModel.inDrawing(DrawingBox(width: 40).graph, kernel: kernel)
        let view = try #require(await app.placeBaseView())
        let dimension = try #require(await app.dimensionBottomEdge(of: view))
        return (app, view, dimension)
    }

    @Test func getSheetProjectsOutsideDrawingMode() async throws {
        let (app, view, dimension) = try await dimensioned()
        app.setMode(.model)
        await app.settle()
        // Lost while the Model is showing: no refresh ran, so only a fresh judgement against a fresh projection can say so.
        try lose(dimension, in: app)
        let (_, core) = rig(app)
        let listed = try await call(core, "list_drawings")
        let sheetID = try #require(listed.result["sheets"]?.array?.first?["id"]?.string)
        let (result, isError) = try await call(core, "get_sheet", .object(["sheet": .string(sheetID)]))
        #expect(!isError)
        #expect(result["complete"]?.bool == true)
        #expect(result["views"]?.array?.first?["id"]?.string == view.rawValue.uuidString)
        #expect(result["views"]?.array?.first?["status"]?.string == "drawn")
        let found = try #require(result["annotations"]?.array?.first { $0["id"]?.string == dimension.rawValue.uuidString })
        #expect(found["status"]?.string == "lost" && found["kind"]?.string == "dimension", "\(found)")
        #expect(found["reason"]?.string == LostReason.missing.sentence)
        #expect(result["parts_list"]?.array?.count == 1)
    }

    @Test func getSheetLeavesAnUncommittedEditorAlone() async throws {
        let (app, _, _) = try await dimensioned()
        #expect(app.drawing.isActive)
        // A live drag: the editor holds a document the model doesn't yet.
        var live = app.drawing.editor.document
        live.sheets[0].name = "Dragging"
        app.drawing.editor.replaceDocument(live)
        let (_, core) = rig(app)
        let listed = try await call(core, "list_drawings")
        let sheetID = try #require(listed.result["sheets"]?.array?.first?["id"]?.string)
        let (_, isError) = try await call(core, "get_sheet", .object(["sheet": .string(sheetID)]))
        #expect(!isError)
        #expect(app.drawing.editor.document == live)
        #expect(app.drawing.editor.document != app.document.drawings)
    }

    @Test func exportIsRefusedWhileEditsAre() async throws {
        var builder = GraphBuilder()
        _ = builder.sketchedBox()
        let app = await AppModel.inDrawing(builder.graph)
        await app.placeBaseView()
        app.setMode(.model)
        let (_, core) = rig(app)
        let url = temporaryURL("refused.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let arguments = JSONValue.object(["kind": .string("pdf"), "path": .string(url.path)])
        app.alert = .problem(AppProblem("Something failed", "It did."))
        let alerted = try await call(core, "export_drawing", arguments)
        #expect(alerted.isError)
        #expect(alerted.result.string == "MetalCreator is asking you something. Answer it, then try again.")
        app.alert = nil
        let sketchNode = try #require(app.document.graph.nodes.values.first { $0.typeID == SketchNode.typeID })
        app.beginSketch(for: sketchNode.id)
        await app.settle()
        let sketching = try await call(core, "export_drawing", arguments)
        #expect(sketching.isError)
        #expect(sketching.result.string == "MetalCreator is editing a sketch. Click Finish in the sketch toolbar, then try again.")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let read = try await call(core, "list_drawings")
        #expect(!read.isError, "reads work in every mode")
    }

    @Test func getSheetAnswersAtTheLimit() async throws {
        let kernel = FakeKernel()
        let box = DrawingBox(width: 40)
        let app = await AppModel.inDrawing(box.graph, kernel: kernel)
        let view = try #require(await app.placeBaseView())
        let (session, core) = rig(app)
        session.drawingSettleLimit = .milliseconds(300)
        let gate = HookGate()
        defer { gate.open() }
        await kernel.setProjectionHook { await gate.hold() }
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(60)), name: "Wider")
        await app.document.waitForEvaluation()
        app.refreshDrawing()
        #expect(await gate.waitUntilEntered())
        let sheetID = try #require(app.drawing.editor.document.sheets.first?.id.rawValue.uuidString)
        let (result, isError) = try await call(core, "get_sheet", .object(["sheet": .string(sheetID)]))
        #expect(!isError)
        #expect(result["complete"]?.bool == false)
        let status = try #require(result["views"]?.array?.first { $0["id"]?.string == view.rawValue.uuidString })
        #expect(status["status"]?.string == "pending")
        let url = temporaryURL("pending.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let refused = try await call(core, "export_drawing", .object(["kind": .string("pdf"), "path": .string(url.path)]))
        #expect(refused.isError)
        #expect(refused.result.string == "MetalCreator is still drawing this sheet. Try again in a moment.")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        gate.open()
        await app.settle()
    }

    @Test func exportWritesAndWarns() async throws {
        let (app, _, dimension) = try await dimensioned()
        try lose(dimension, in: app)
        app.refreshDrawing()
        await app.settle()
        let (_, core) = rig(app)
        let url = temporaryURL("written.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let sheetName = try #require(app.drawing.editor.document.sheets.first?.name)
        let (result, isError) = try await call(core, "export_drawing", .object([
            "kind": .string("pdf_sheet"), "sheet": .string(sheetName), "path": .string(url.path),
        ]))
        #expect(!isError)
        let message = try #require(result["message"]?.string)
        #expect(message.hasPrefix("Exported \(url.lastPathComponent) with "), "\(message) \(result)")
        #expect(message.contains("lost what it was attached to"), "\(message)")
        let bytes = try Data(contentsOf: url)
        #expect(bytes.starts(with: Data("%PDF".utf8)))
    }

    @Test func anExistingFileNeedsOverwrite() async throws {
        let (app, _, _) = try await dimensioned()
        let (_, core) = rig(app)
        let url = temporaryURL("exists.svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old".utf8).write(to: url)
        let sheetName = try #require(app.drawing.editor.document.sheets.first?.name)
        let arguments: [String: JSONValue] = ["kind": .string("svg_sheet"), "sheet": .string(sheetName), "path": .string(url.path)]
        let refused = try await call(core, "export_drawing", .object(arguments))
        #expect(refused.isError && refused.result.string == "\(url.lastPathComponent) already exists. Pass overwrite to replace it.")
        #expect(try Data(contentsOf: url) == Data("old".utf8))
        var replacing = arguments
        replacing["overwrite"] = .bool(true)
        let done = try await call(core, "export_drawing", .object(replacing))
        #expect(!done.isError)
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("<?xml"))
    }
}

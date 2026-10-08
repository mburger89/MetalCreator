import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// New, Open, Save and Save As (spec §6.1, §4.5): the document's file, whether it's edited, and the alerts.
@MainActor
struct AppModelFileTests {
    @Test func aNewAppIsAnUntitledUneditedEmptyDocument() async {
        let app = await makeApp()
        #expect(app.displayName == "Untitled")
        #expect(app.fileURL == nil)
        #expect(!app.isEdited)
        #expect(app.document.graph.nodes.isEmpty)
        #expect(app.document.viewState.dock == .left, "the graph panel starts docked left (spec §6.1)")
    }

    @Test func savingWritesTheFileAndReopeningRestoresTheGraph() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = await makeApp()
        try app.document.perform(.batch(builder.graph.nodes.values.sorted { $0.id < $1.id }.map { .addNode($0) }
            + [.restoreLinks(builder.graph.links)]))
        #expect(app.isEdited)
        let url = temporaryURL("box.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        #expect(!app.isEdited)
        #expect(app.fileURL == url)
        #expect(app.displayName == url.lastPathComponent)

        let reopened = await makeApp()
        try reopened.open(url)
        await reopened.settle()
        #expect(reopened.document.graph == app.document.graph)
        #expect(!reopened.isEdited)
        #expect(reopened.viewport.items.count == 1, "the reopened box is shown")
    }

    @Test func openingReplacesTheDocumentWithFreshPartsAndStartsOver() async throws {
        let app = await makeApp()
        app.previewMode = .selectedNode
        let url = temporaryURL("empty.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try GraphFileIO.encode(GraphFile(viewState: ViewState(dock: .bottom))).write(to: url)
        let (document, editor, viewport) = (app.document, app.editor, app.viewport)
        try app.open(url)
        #expect(app.document !== document && app.editor !== editor && app.viewport !== viewport)
        #expect(app.graphInput.model === app.editor)
        #expect(app.editor.dock == .bottom)
        #expect(app.previewMode == .final)
    }

    @Test func aFileFromANewerMetalCreatorIsRefusedInPlainWords() async throws {
        let app = await makeApp()
        let url = temporaryURL("future.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"formatVersion": 99, "graph": {"nodes": []}}"#.utf8).write(to: url)
        let document = app.document
        #expect(throws: AppProblem("“\(url.lastPathComponent)” couldn't be opened",
                                   GraphFileError.newerFormat(99).message)) {
            try app.open(url)
        }
        #expect(app.document === document, "the open document is kept")
    }

    @Test func aFileThatIsntAGraphIsRefused() async throws {
        let app = await makeApp()
        let url = temporaryURL("notes.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("hello".utf8).write(to: url)
        #expect(throws: AppProblem("“\(url.lastPathComponent)” couldn't be opened",
                                   "It isn't a MetalCreator graph, or it is damaged.")) {
            try app.open(url)
        }
    }

    @Test func newAsksBeforeDiscardingChanges() async throws {
        let app = await makeApp()
        try app.document.perform(.addNode(BuiltInNodes.registry.makeNode(NumberNode.typeID)))
        app.newDocument()
        #expect(app.alert?.title == "Discard unsaved changes?")
        #expect(app.document.graph.nodes.count == 1, "nothing is discarded until the person says so")
        app.keepChanges()
        #expect(app.alert == nil && app.pendingDiscard == nil, "Cancel forgets the request")
        await app.discardChanges()
        #expect(app.document.graph.nodes.count == 1, "a later Discard has nothing to carry on with")
        app.newDocument()
        await app.discardChanges()
        #expect(app.document.graph.nodes.isEmpty)
        #expect(!app.isEdited)
    }

    @Test func openWithChangesAsksThenOpensThePickedFile() async throws {
        let url = temporaryURL("picked.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        var builder = GraphBuilder()
        _ = builder.box()
        try GraphFileIO.encode(GraphFile(graph: builder.graph)).write(to: url)
        let app = await makeApp()
        try app.document.perform(.addNode(BuiltInNodes.registry.makeNode(NumberNode.typeID)))
        let picker = ScriptedPicker([url])
        await app.openDocument(using: picker)
        #expect(app.alert != nil)
        #expect(picker.asked.isEmpty, "the panel waits for the answer")
        await app.discardChanges()
        #expect(picker.asked.first?.types == [.mcgraph])
        #expect(app.fileURL == url)
        #expect(app.document.graph.nodes == builder.graph.nodes)
        #expect(Set(app.document.graph.links) == Set(builder.graph.links))
    }

    @Test func saveAsSavesWhereThePickerSaysAndACancelSavesNothing() async throws {
        let app = await makeApp()
        try app.document.perform(.addNode(BuiltInNodes.registry.makeNode(NumberNode.typeID)))
        #expect(await app.saveDocument(using: ScriptedPicker([nil])) == false, "a new document asks where; cancelled")
        #expect(app.isEdited)
        let url = temporaryURL("saved.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let picker = ScriptedPicker([url])
        #expect(await app.saveDocument(using: picker))
        #expect(picker.asked.first?.name == "Untitled.mcgraph")
        #expect(!app.isEdited)
        #expect(FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func theCameraIsSavedOnceItHasSettledAndTheHomeViewWithIt() async throws {
        let app = await makeApp()
        let url = temporaryURL("camera.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        #expect(try GraphFileIO.decode(Data(contentsOf: url), registry: BuiltInNodes.registry).viewState.camera == nil,
                "a camera that never settled isn't saved, so reopening frames the part")
        app.viewport.perform(.projection(.orthographic))
        app.viewport.perform(.setHome)
        #expect(app.document.viewState.camera?.projection == .orthographic)
        #expect(app.document.viewState.homeCamera == app.viewport.homePose)
        try app.save(to: url)
        let saved = try GraphFileIO.decode(Data(contentsOf: url), registry: BuiltInNodes.registry).viewState
        #expect(saved.camera == app.viewport.pose)
        #expect(saved.homeCamera == app.viewport.homePose)
        try app.open(url)
        #expect(app.viewport.pose == saved.camera, "the reopened viewport starts at the saved camera")
        #expect(app.viewport.homePose == saved.homeCamera)
    }
}

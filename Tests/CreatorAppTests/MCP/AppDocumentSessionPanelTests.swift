import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import Foundation
import MetalUI
import Testing
@testable import CreatorApp
@testable import CreatorEditor
@testable import CreatorMCP

// MARK: Export sheet, file panels and held results (MCP-1b B)

/// A file picker whose panel stays up until `release`d, then answers `answer` (or throws `failure`).
@MainActor
private final class GatedFilePicker: FilePicker {
    var failure: (any Error)?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var asked = 0

    func chooseFileToOpen(_ types: [ContentType]) async throws -> URL? { try await gate() }
    func chooseDestination(_ types: [ContentType], defaultName: String) async throws -> URL? { try await gate() }

    private func gate() async throws -> URL? {
        asked += 1
        await withCheckedContinuation { waiting.append($0) }
        if let failure { throw failure }
        return nil
    }

    func release() {
        let all = waiting
        waiting = []
        for continuation in all { continuation.resume() }
    }
}

extension AppDocumentSessionTests {
    private func meshGraph() -> Graph {
        var builder = GraphBuilder()
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(10)])
        let mesh = builder.add(MeshNode.self, ["export resolution": .number(0.05)])
        let output = builder.add(OutputNode.self)
        builder.wire(sphere, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        return builder.graph
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<2000 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition())
    }

    private static let exportSentence =
        "MetalCreator is exporting a file. Wait for it to finish, or cancel it in the export window, then try again."
    private static let panelSentence = "MetalCreator is showing a file panel. Choose a file or cancel the panel, then try again."
    private static let heldSentence = "MetalCreator is checking a change in the window. Try again in a moment."
    private static let alertSentence = "MetalCreator is asking you something. Answer it, then try again."

    @Test func exportSheetRefusesEdits() async throws {
        let (app, session, core) = await rig(meshGraph())
        app.exportHold = { try await Task.sleep(for: .seconds(3600)) }
        let url = temporaryURL("mcp-sheet.3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        let task = Task { try await app.export(.threeMF, to: url) }
        try await waitUntil { app.exportRun != nil }
        let added = try await call(core, "add_node", .object(["type": .string("creator.rectangle")]))
        #expect(added.isError && added.result.string == Self.exportSentence)
        for tool in ["undo", "redo", "new_document"] {
            let outcome = try await call(core, tool)
            #expect(outcome.isError && outcome.result.string == Self.exportSentence, "\(tool)")
        }
        let other = temporaryURL("mcp-sheet.mcgraph")
        for (tool, arguments) in [("open_document", JSONValue.object(["path": .string(other.path)])),
                                  ("save_document", .object(["path": .string(other.path)])),
                                  ("set_file", .object(["node": .string(UUID().uuidString), "path": .string(other.path)])),
        ] {
            let outcome = try await call(core, tool, arguments)
            #expect(outcome.isError && outcome.result.string == Self.exportSentence, "\(tool)")
        }
        #expect(session.editRefusal() == Self.exportSentence)
        app.exportRun?.cancel()
        _ = try? await task.value
        try await waitUntil { app.exportRun == nil }
        let after = try await call(core, "add_node", .object(["type": .string("creator.rectangle")]))
        #expect(!after.isError)
    }

    @Test func filePanelRefusesEditsAndFileTools() async throws {
        let (app, session, core) = await rig()
        let picker = GatedFilePicker()
        let task = Task { await app.openDocument(using: picker) }
        try await waitUntil { app.filePanels.isOpen }
        #expect(session.editRefusal() == Self.panelSentence)
        let added = try await call(core, "add_node", .object(["type": .string("creator.rectangle")]))
        #expect(added.isError && added.result.string == Self.panelSentence)
        picker.release()
        await task.value
        #expect(session.editRefusal() == nil)
    }

    @Test func aPickerThatThrowsReleasesThePanel() async throws {
        let (app, session, core) = await rig()
        let picker = GatedFilePicker()
        picker.failure = FileDialogError.busy
        let task = Task { await app.openDocument(using: picker) }
        try await waitUntil { app.filePanels.isOpen }
        picker.release()
        await task.value
        app.alert = nil
        #expect(!app.filePanels.isOpen)
        #expect(session.editRefusal() == nil)
        let added = try await call(core, "add_node", .object(["type": .string("creator.rectangle")]))
        #expect(!added.isError)
    }

    @Test func everyPickerEntryPointIsTracked() async throws {
        var builder = GraphBuilder()
        builder.graph = meshGraph()
        let image = builder.add(ImageFieldNode.self)
        let meshFile = builder.add(ImportMeshNode.self)
        let (app, _, _) = await rig(builder.graph)
        let entries: [(String, @MainActor (GatedFilePicker) async -> Void)] = [
            ("open", { await app.openDocument(using: $0) }),
            ("save as", { _ = await app.saveDocumentAs(using: $0) }),
            ("choose image", { await app.performImage(.chooseImage, on: image.id, using: $0) }),
            ("relink image", { await app.performImage(.relinkImage, on: image.id, using: $0) }),
            ("choose mesh", { await app.performMeshFile(.chooseMeshFile, on: meshFile.id, using: $0) }),
            ("relink mesh", { await app.performMeshFile(.relinkMeshFile, on: meshFile.id, using: $0) }),
            ("import mesh", { await app.importMesh(using: $0) }),
            ("export destination", { await app.exportDocument(.threeMF, using: $0) }),
        ]
        for (name, start) in entries {
            let picker = GatedFilePicker()
            let task = Task { await start(picker) }
            try await waitUntil { picker.asked > 0 }
            #expect(app.filePanels.isOpen, "\(name)")
            picker.release()
            await task.value
            app.alert = nil
            #expect(!app.filePanels.isOpen, "\(name) releases")
        }
    }

    @Test func heldResultsRefuseEdits() async throws {
        let (app, session, _) = await rig()
        app.document.holdResults()
        #expect(session.editRefusal() == Self.heldSentence)
        app.document.releaseResults()
        #expect(session.editRefusal() == nil)
    }

    @Test func refusalOrderIsStable() async throws {
        let (app, session, _) = await rig(meshGraph())
        app.exportHold = { try await Task.sleep(for: .seconds(3600)) }
        let url = temporaryURL("mcp-order.3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        let export = Task { try await app.export(.threeMF, to: url) }
        try await waitUntil { app.exportRun != nil }
        let picker = GatedFilePicker()
        let panel = Task { await app.openDocument(using: picker) }
        try await waitUntil { app.filePanels.isOpen }
        app.alert = .problem(AppProblem("Something failed", "It did."))
        #expect(session.editRefusal() == Self.alertSentence)
        app.alert = nil
        #expect(session.editRefusal() == Self.exportSentence)
        app.exportRun?.cancel()
        _ = try? await export.value
        try await waitUntil { app.exportRun == nil }
        app.document.holdResults()
        #expect(session.editRefusal() == Self.panelSentence)
        app.document.releaseResults()
        picker.release()
        await panel.value
    }

    @Test func aClientsOwnExportIsNotRefusedByItself() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let (_, _, core) = await rig(builder.graph)
        let url = temporaryURL("mcp-own.3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await call(core, "export", .object(["kind": .string("3mf"), "path": .string(url.path)]))
        #expect(!result.isError)
    }

    @Test func themeEditorPanelDoesNotRefuse() async throws {
        let (app, session, _) = await rig()
        let editor = ThemeEditorModel(themes: ThemeStore())
        let picker = GatedFilePicker()
        let task = Task { await editor.importTheme(using: picker) }
        try await waitUntil { picker.asked > 0 }
        #expect(session.editRefusal() == nil)
        #expect(!app.filePanels.isOpen)
        picker.release()
        await task.value
    }
}

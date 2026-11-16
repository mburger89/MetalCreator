import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// Import KiCad Board's buttons and File ▸ Import KiCad Board… (KiCad import spec, the app).
@MainActor
struct BoardFileActionsTests {
    let folder = AppTempFolder()
    let board = Data("(kicad_pcb (version 20260206))\n".utf8)

    func boardApp(_ setting: ImageReference? = nil) async -> (AppModel, Node) {
        var builder = GraphBuilder()
        let node = builder.add(ImportKiCadBoardNode.self)
        var graph = builder.graph
        graph.nodes[node.id]?.isOutput = true
        if let setting { graph.nodes[node.id]?.inputValues[NodeSetting.pcbFile] = .pcbFile(setting) }
        let app = await makeApp(graph)
        return (app, graph.nodes[node.id] ?? node)
    }

    func setting(_ app: AppModel, _ node: Node) -> ImageReference? {
        app.document.graph.nodes[node.id]?.inputValues[NodeSetting.pcbFile]?.fileReference
    }

    @Test func importInsertsNodeAndOutputAsOneStep() async throws {
        let app = await makeApp()
        let file = try folder.write(board, to: "keyboard.kicad_pcb")
        await app.importKiCadBoard(using: ScriptedPicker([file]))
        let node = try #require(app.document.graph.nodes.values.first { $0.typeID == ImportKiCadBoardNode.typeID })
        let output = try #require(app.document.graph.nodes.values.first { $0.typeID == OutputNode.typeID })
        #expect(node.inputValues[NodeSetting.pcbFile]?.fileReference?.fileName == "keyboard.kicad_pcb")
        #expect(app.document.graph.links.contains(Link(from: Endpoint(node: node.id, socket: "board"),
                                                       to: Endpoint(node: output.id, socket: "solid"))))
        #expect(app.document.undoName == "Import KiCad Board" && app.editor.selection == [node.id])
        app.document.undo()
        #expect(app.document.graph.nodes.isEmpty)
    }

    @Test func importInsideAGroupInsertsTheNodeAlone() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        let file = try folder.write(board, to: "keyboard.kicad_pcb")
        await app.importKiCadBoard(using: ScriptedPicker([file]))
        #expect(app.alert == nil)
        #expect(app.editor.graph.nodes.values.contains { $0.typeID == ImportKiCadBoardNode.typeID })
        #expect(!app.editor.graph.nodes.values.contains { $0.typeID == OutputNode.typeID })
    }

    @Test func importIsDisabledInSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.beginSketch(for: box.sketch.id)
        try #require(app.sketch != nil)
        #expect(!app.canImportKiCadBoard)
        let picker = ScriptedPicker([try folder.write(board, to: "keyboard.kicad_pcb")])
        await app.importKiCadBoard(using: picker)
        #expect(picker.asked.isEmpty && !app.document.graph.nodes.values.contains { $0.typeID == ImportKiCadBoardNode.typeID })
    }

    @Test func chooseLinksAndRefusesAFolder() async throws {
        let (app, node) = await boardApp()
        await app.performBoardFile(.choosePCBFile, on: node.id, using: ScriptedPicker([folder.url]))
        #expect(setting(app, node) == nil && app.alert?.message.contains("isn't a file") == true)
        app.alert = nil
        let file = try folder.write(board, to: "keyboard.kicad_pcb")
        let picker = ScriptedPicker([file])
        await app.performBoardFile(.choosePCBFile, on: node.id, using: picker)
        #expect(picker.asked.map(\.types) == [[.kicadPCB]])
        #expect(setting(app, node)?.isEmbedded == false && app.document.undoName == "Choose Board File")
    }

    @Test func relinkChangesTheSettingWithItsOwnName() async throws {
        let gone = ImageReference.linked(relativePath: nil, absolutePath: folder.url.appending(path: "gone.kicad_pcb").path)
        let (app, node) = await boardApp(gone)
        let file = try folder.write(board, to: "keyboard.kicad_pcb")
        await app.performBoardFile(.relinkPCBFile, on: node.id, using: ScriptedPicker([file]))
        #expect(setting(app, node)?.fileName == "keyboard.kicad_pcb" && app.document.undoName == "Relink Board File")
    }

    @Test func aButtonPressedInTheEditorReachesTheAppShell() async throws {
        let (app, node) = await boardApp()
        let file = try folder.write(board, to: "keyboard.kicad_pcb")
        app.filePicker = ScriptedPicker([file])
        app.editor.press(.choosePCBFile, on: node.id)
        let request = try #require(app.editor.inspectorRequest)
        let task = try #require(app.handleBoardFile(request))
        await task.value
        #expect(setting(app, node)?.fileName == "keyboard.kicad_pcb")
    }

    @Test func importIgnoresAPanelAnsweredAfterTheDocumentChanged() async throws {
        let app = await makeApp()
        let file = try folder.write(board, to: "keyboard.kicad_pcb")
        await app.importKiCadBoard(using: InterruptedPicker(answer: file) { app.newDocument() })
        #expect(app.alert == nil && app.document.graph.nodes.isEmpty && !app.isEdited)
    }

    @Test func aPanelAnsweredAfterTheNodeWentChangesNothing() async throws {
        let (app, node) = await boardApp()
        let file = try folder.write(board, to: "keyboard.kicad_pcb")
        let picker = InterruptedPicker(answer: file) { try? app.document.perform(.removeNode(node.id)) }
        await app.performBoardFile(.choosePCBFile, on: node.id, using: picker)
        #expect(app.document.graph.nodes[node.id] == nil && app.alert == nil)
        #expect(app.document.undoName != "Choose Board File")
    }

    @Test func embeddingIsRefused() async throws {
        let (app, node) = await boardApp()
        let file = try folder.write(board, to: "keyboard.kicad_pcb")
        do {
            try app.setBoardFile(file, on: node.id, embed: true)
            Issue.record("expected a refusal")
        } catch {
            #expect(error.message == "A KiCad board is always linked, never embedded.")
        }
        #expect(setting(app, node) == nil)
        try app.setBoardFile(file, on: node.id, embed: false)
        #expect(setting(app, node)?.fileName == "keyboard.kicad_pcb")
    }

    @Test func aFileDialogDeclaresItsExtensions() {
        #expect(AppModel.boardTypes.map(\.preferredFilenameExtension) == ["kicad_pcb"])
    }
}

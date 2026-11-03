import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// Import Mesh's buttons and File ▸ Import Mesh… (mesh import spec, the app): choosing, relinking and embedding a file through the
/// file panels, the refusals, and the nodes a menu import inserts.
@MainActor
struct MeshFileActionsTests {
    let folder = AppTempFolder()
    let stl = Data("""
        solid t
        facet normal 0 0 -1
        outer loop
        vertex 0 0 0
        vertex 0 10 0
        vertex 10 0 0
        endloop
        endfacet
        facet normal 0 0 -1
        outer loop
        vertex 0 0 0
        vertex 10 0 0
        vertex 0 0 10
        endloop
        endfacet
        endsolid t
        """.utf8)

    func meshApp(_ setting: ImageReference? = nil) async -> (AppModel, Node) {
        var builder = GraphBuilder()
        let node = builder.add(ImportMeshNode.self)
        var graph = builder.graph
        graph.nodes[node.id]?.isOutput = true
        if let setting { graph.nodes[node.id]?.inputValues[NodeSetting.meshFile] = .meshFile(setting) }
        let app = await makeApp(graph)
        return (app, graph.nodes[node.id] ?? node)
    }

    func setting(_ app: AppModel, _ node: Node) -> ImageReference? {
        app.document.graph.nodes[node.id]?.inputValues[NodeSetting.meshFile]?.fileReference
    }

    // MARK: Buttons

    @Test func chooseLinksAndIsOneUndoStep() async throws {
        let (app, node) = await meshApp()
        let file = try folder.write(stl, to: "part.stl")
        let picker = ScriptedPicker([file])
        await app.performMeshFile(.chooseMeshFile, on: node.id, using: picker)
        #expect(picker.asked.map(\.types) == [[.stl]])
        #expect(setting(app, node)?.fileName == "part.stl" && setting(app, node)?.isEmbedded == false)
        #expect(app.document.images.isEmpty && app.document.undoName == "Choose Mesh File")
        app.document.undo()
        #expect(setting(app, node) == nil && !app.isEdited)
    }

    @Test func chooseRefusesAFolderAndChangesNothing() async throws {
        let (app, node) = await meshApp()
        await app.performMeshFile(.chooseMeshFile, on: node.id, using: ScriptedPicker([folder.url]))
        #expect(setting(app, node) == nil && app.alert?.message.contains("isn't a file") == true)
        guard case .problem(let problem)? = app.alert else { Issue.record("no problem"); return }
        #expect(problem.title == "That mesh file can't be used")
    }

    @Test func aBadMeshFileIsChosenAndTheNodeSaysWhatIsWrong() async throws {
        let (app, node) = await meshApp()
        let zip = try folder.write(Data("PK\u{3}\u{4}....".utf8), to: "model.stl")
        await app.performMeshFile(.chooseMeshFile, on: node.id, using: ScriptedPicker([zip]))
        #expect(setting(app, node) != nil && app.alert == nil)
        await app.settle()
        guard case .error(let message)? = app.document.results[node.id]?.state else { Issue.record("expected a failure"); return }
        #expect(message.contains("isn't an STL or 3MF"), "\(message)")
    }

    @Test func relinkKeepsPlacement() async throws {
        let (app, node) = await meshApp(.linked(relativePath: nil, absolutePath: folder.url.appending(path: "gone.stl").path))
        try app.document.perform(.setInput(node.id, "units", .integer(2)))
        let file = try folder.write(stl, to: "part.stl")
        await app.performMeshFile(.relinkMeshFile, on: node.id, using: ScriptedPicker([file]))
        #expect(setting(app, node)?.fileName == "part.stl" && app.document.undoName == "Relink Mesh File")
        #expect(app.document.graph.nodes[node.id]?.inputValues["units"] == .integer(2))
        await app.settle()
        #expect(app.document.results[node.id]?.state.isSuccess == true)
    }

    @Test func embedStoresTheBytesAndUndoRestoresTheLink() async throws {
        let file = try folder.write(stl, to: "part.stl")
        let link = ImageReference.linked(relativePath: nil, absolutePath: file.path)
        let (app, node) = await meshApp(link)
        await app.performMeshFile(.embedMeshFile, on: node.id, using: ScriptedPicker([]))
        let hash = ImageHash(of: stl)
        #expect(setting(app, node) == .embedded(hash) && app.document.images[hash] == stl)
        #expect(app.document.undoName == "Embed Mesh File")
        app.document.undo()
        #expect(setting(app, node) == link)
    }

    @Test func embedOverTheLimitRefusesAndChangesNothing() async throws {
        let big = Data(count: MeshImportLimits.maxEmbeddedBytes + 1)
        let file = try folder.write(big, to: "big.stl")
        let link = ImageReference.linked(relativePath: nil, absolutePath: file.path)
        let (app, node) = await meshApp(link)
        await app.performMeshFile(.embedMeshFile, on: node.id, using: ScriptedPicker([]))
        #expect(setting(app, node) == link && app.document.images.isEmpty)
        #expect(app.alert?.message == "This file is larger than the 64 MB limit for embedding.")
        #expect(MeshImportLimits.embeddingRefusal == app.alert?.message)
        #expect(!app.isEdited)
    }

    @Test func aMissingLinkOpensTheDocumentAndOffersRelink() async throws {
        var builder = GraphBuilder()
        let gone = ImageReference.linked(relativePath: nil, absolutePath: folder.url.appending(path: "gone.stl").path)
        let mesh = builder.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(gone)])
        let box = builder.box()
        var graph = builder.graph
        graph.nodes[mesh.id]?.isOutput = true
        let app = await makeApp(graph)
        await app.settle()
        #expect(app.document.results[mesh.id]?.state.isSuccess == false)
        #expect(app.document.results[box.extrude.id]?.state.isSuccess == true, "other nodes evaluate")
        app.editor.selection = [mesh.id]
        let rows = app.editor.inspectorPage.sections.first { $0.title == "File" }?.rows ?? []
        #expect(rows.contains(.button(title: "Relink…", action: .relinkMeshFile)))
    }

    @Test func aButtonPressedInTheEditorReachesTheAppShell() async throws {
        let (app, node) = await meshApp()
        let file = try folder.write(stl, to: "part.stl")
        app.filePicker = ScriptedPicker([file])
        app.editor.press(.chooseMeshFile, on: node.id)
        let request = try #require(app.editor.inspectorRequest)
        let task = try #require(app.handleMeshFile(request))
        await task.value
        #expect(setting(app, node)?.fileName == "part.stl")
    }

    // MARK: File ▸ Import Mesh…

    @Test func importMeshInsertsNodeAndOutputAsOneStep() async throws {
        let app = await makeApp()
        let file = try folder.write(stl, to: "part.stl")
        await app.importMesh(using: ScriptedPicker([file]))
        let mesh = try #require(app.document.graph.nodes.values.first { $0.typeID == ImportMeshNode.typeID })
        let output = try #require(app.document.graph.nodes.values.first { $0.typeID == OutputNode.typeID })
        #expect(mesh.inputValues[NodeSetting.meshFile]?.fileReference?.fileName == "part.stl")
        #expect(app.document.graph.links.contains(Link(from: Endpoint(node: mesh.id, socket: "mesh"),
                                                       to: Endpoint(node: output.id, socket: "mesh"))))
        #expect(app.document.undoName == "Import Mesh" && app.editor.selection == [mesh.id])
        app.document.undo()
        #expect(app.document.graph.nodes.isEmpty)
    }

    @Test func importMeshInsideAGroupInsertsTheNodeAlone() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        let file = try folder.write(stl, to: "part.stl")
        await app.importMesh(using: ScriptedPicker([file]))
        #expect(app.alert == nil)
        #expect(app.editor.graph.nodes.values.contains { $0.typeID == ImportMeshNode.typeID })
        #expect(!app.editor.graph.nodes.values.contains { $0.typeID == OutputNode.typeID })
        #expect(app.document.undoName == "Import Mesh")
    }

    @Test func importMeshIsDisabledInSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.beginSketch(for: box.sketch.id)
        try #require(app.sketch != nil)
        #expect(!app.canImportMesh)
        let picker = ScriptedPicker([try folder.write(stl, to: "part.stl")])
        await app.importMesh(using: picker)
        #expect(picker.asked.isEmpty && !app.document.graph.nodes.values.contains { $0.typeID == ImportMeshNode.typeID })
    }

    // MARK: Late answers

    @Test func importMeshIgnoresAPanelAnsweredAfterTheDocumentChanged() async throws {
        let app = await makeApp()
        let file = try folder.write(stl, to: "part.stl")
        await app.importMesh(using: InterruptedPicker(answer: file) { app.newDocument() })
        #expect(app.alert == nil && app.document.graph.nodes.isEmpty && !app.isEdited)
    }

    @Test func importMeshIgnoresAPanelAnsweredAfterTheLevelChanged() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        let file = try folder.write(stl, to: "part.stl")
        await app.importMesh(using: InterruptedPicker(answer: file) { app.editor.goToLevel(0) })
        #expect(!app.document.graph.nodes.values.contains { $0.typeID == ImportMeshNode.typeID } && app.alert == nil)
    }

    @Test func aSecondImportMeshWhileAPanelIsOpenDoesNothing() async throws {
        let app = await makeApp()
        let file = try folder.write(stl, to: "part.stl")
        let second = ScriptedPicker([try folder.write(stl, to: "other.stl")])
        let picker = InterruptedPicker(answer: file) {
            #expect(!app.canImportMesh)
            await app.importMesh(using: second)
        }
        await app.importMesh(using: picker)
        #expect(second.asked.isEmpty)
        #expect(app.document.graph.nodes.values.filter { $0.typeID == ImportMeshNode.typeID }.count == 1)
        #expect(app.canImportMesh)
    }

    @Test(arguments: [InspectorAction.chooseMeshFile, .relinkMeshFile])
    func aMeshFilePanelAnsweredAfterTheNodeWentChangesNothing(_ action: InspectorAction) async throws {
        let (app, node) = await meshApp()
        let file = try folder.write(stl, to: "part.stl")
        let picker = InterruptedPicker(answer: file) { try? app.document.perform(.removeNode(node.id)) }
        await app.performMeshFile(action, on: node.id, using: picker)
        #expect(app.document.graph.nodes[node.id] == nil && app.alert == nil)
        #expect(app.document.undoName != "Choose Mesh File" && app.document.undoName != "Relink Mesh File")
    }

    @Test func aMeshFilePanelAnsweredAfterANewDocumentChangesNothing() async throws {
        let (app, node) = await meshApp()
        let file = try folder.write(stl, to: "part.stl")
        await app.performMeshFile(.chooseMeshFile, on: node.id, using: InterruptedPicker(answer: file) { app.newDocument() })
        #expect(app.alert == nil && !app.isEdited)
    }

    @Test func aLinkBeforeTheFirstSaveGainsARelativePath() async throws {
        let (app, node) = await meshApp()
        let file = try folder.write(stl, to: "meshes/part.stl")
        await app.performMeshFile(.chooseMeshFile, on: node.id, using: ScriptedPicker([file]))
        let absolute = file.standardizedFileURL.path(percentEncoded: false)
        #expect(setting(app, node) == .linked(relativePath: nil, absolutePath: absolute))
        try app.save(to: folder.url.appending(path: "Plate.mcgraph"))
        #expect(setting(app, node) == .linked(relativePath: "meshes/part.stl", absolutePath: absolute))
    }

    @Test func aFileDialogDeclaresItsExtensions() {
        #expect(AppModel.meshTypes == [.stl])
        #expect(AppModel.meshTypes.map(\.preferredFilenameExtension) == ["stl"])
    }
}

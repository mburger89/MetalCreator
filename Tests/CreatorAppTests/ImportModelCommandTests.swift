import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// Import Model's buttons and File ▸ Import Model… (NURBS spec, Task 8).
@MainActor
struct ImportModelCommandTests {
    let folder = AppTempFolder()
    /// Not a model, but a file: choosing never judges what a file holds, the node does.
    let bytes = Data("ISO-10303-21;\nEND-ISO-10303-21;\n".utf8)

    func modelApp(_ setting: ImageReference? = nil) async -> (AppModel, Node) {
        var builder = GraphBuilder()
        let node = builder.add(ImportModelNode.self)
        var graph = builder.graph
        graph.nodes[node.id]?.isOutput = true
        if let setting { graph.nodes[node.id]?.inputValues[NodeSetting.modelFile] = .modelFile(setting) }
        let app = await makeApp(graph)
        return (app, graph.nodes[node.id] ?? node)
    }

    func setting(_ app: AppModel, _ node: Node) -> ImageReference? {
        app.document.graph.nodes[node.id]?.inputValues[NodeSetting.modelFile]?.fileReference
    }

    @Test func importInsertsNodeAndOutputAsOneNamedStep() async throws {
        let app = await makeApp()
        let file = try folder.write(bytes, to: "bracket.step")
        await app.importModel(using: ScriptedPicker([file]))
        let node = try #require(app.document.graph.nodes.values.first { $0.typeID == ImportModelNode.typeID })
        let output = try #require(app.document.graph.nodes.values.first { $0.typeID == OutputNode.typeID })
        #expect(node.inputValues[NodeSetting.modelFile]?.fileReference?.fileName == "bracket.step")
        #expect(node.inputValues[NodeSetting.modelFile]?.fileReference?.isEmbedded == false)
        #expect(app.document.graph.links.contains(Link(from: Endpoint(node: node.id, socket: "solids"),
                                                       to: Endpoint(node: output.id, socket: "solid"))))
        #expect(app.document.graph.links.contains(Link(from: Endpoint(node: node.id, socket: "curves"),
                                                       to: Endpoint(node: output.id, socket: "curve"))))
        #expect(app.document.undoName == "Import Model" && app.editor.selection == [node.id])
        app.document.undo()
        #expect(app.document.graph.nodes.isEmpty)
        #expect(app.document.undoName != "Import Model")
    }

    @Test func importInsideAGroupInsertsTheNodeAlone() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        await app.importModel(using: ScriptedPicker([try folder.write(bytes, to: "bracket.step")]))
        #expect(app.alert == nil)
        #expect(app.editor.graph.nodes.values.contains { $0.typeID == ImportModelNode.typeID })
        #expect(!app.editor.graph.nodes.values.contains { $0.typeID == OutputNode.typeID })
    }

    @Test func importIsDisabledInSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.beginSketch(for: box.sketch.id)
        try #require(app.sketch != nil)
        #expect(!app.canImportModel)
        let picker = ScriptedPicker([try folder.write(bytes, to: "bracket.step")])
        await app.importModel(using: picker)
        #expect(picker.asked.isEmpty && !app.document.graph.nodes.values.contains { $0.typeID == ImportModelNode.typeID })
    }

    @Test func thePanelOffersStepAndIges() async throws {
        let app = await makeApp()
        let picker = ScriptedPicker([])
        await app.importModel(using: picker)
        let types = try #require(picker.asked.first)
        #expect(types.types == [.step, .iges])
    }

    @Test func chooseLinksAndRefusesAFolder() async throws {
        let (app, node) = await modelApp()
        await app.performModelFile(.chooseModelFile, on: node.id, using: ScriptedPicker([folder.url]))
        #expect(setting(app, node) == nil && app.alert?.message.contains("isn't a file") == true)
        app.alert = nil
        let file = try folder.write(bytes, to: "a.step")
        await app.performModelFile(.chooseModelFile, on: node.id, using: ScriptedPicker([file]))
        #expect(setting(app, node)?.fileName == "a.step" && setting(app, node)?.isEmbedded == false)
        #expect(app.document.undoName == "Choose Model File")
    }

    @Test func relinkAndEmbedAreEachOneStep() async throws {
        let first = try folder.write(bytes, to: "a.step")
        let (app, node) = await modelApp(.linked(relativePath: nil, absolutePath: first.path(percentEncoded: false)))
        let second = try folder.write(bytes + Data("x".utf8), to: "b.step")
        await app.performModelFile(.relinkModelFile, on: node.id, using: ScriptedPicker([second]))
        #expect(setting(app, node)?.fileName == "b.step" && app.document.undoName == "Relink Model File")
        await app.performModelFile(.embedModelFile, on: node.id, using: ScriptedPicker([]))
        #expect(setting(app, node)?.isEmbedded == true && app.document.undoName == "Embed Model File")
        #expect(app.document.imageResolver.embedded.values.contains(bytes + Data("x".utf8)))
    }

    @Test func setModelFileEmbedsFromAPath() async throws {
        let (app, node) = await modelApp()
        let file = try folder.write(bytes, to: "c.step")
        try app.setModelFile(file, on: node.id, embed: true)
        #expect(setting(app, node)?.isEmbedded == true)
    }
}

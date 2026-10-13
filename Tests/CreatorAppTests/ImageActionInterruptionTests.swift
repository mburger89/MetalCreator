import CreatorGraph
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// An image button's file panel can stay open while the person does something else (fields spec §5): the answer is dropped
/// when the document or level has changed, a second press waits, and nothing is written beside a refused link.
@MainActor
struct ImageActionInterruptionTests {
    let folder = AppTempFolder()
    let picture = AppTestImages.png(level: 100)

    func imageApp(_ setting: ImageReference? = nil) async -> (AppModel, Node) {
        var builder = GraphBuilder()
        let node = builder.add(ImageFieldNode.self)
        var graph = builder.graph
        if let setting { graph.nodes[node.id]?.inputValues[NodeSetting.image] = .image(setting) }
        let app = await makeApp(graph)
        return (app, graph.nodes[node.id] ?? node)
    }

    @Test func aNewDocumentWhileThePanelIsOpenKeepsTheChosenFileOutOfIt() async throws {
        let (app, node) = await imageApp()
        let file = try folder.write(picture, to: "vent.png")
        let picker = InterruptedPicker(answer: file) { app.newDocument() }
        await app.performImage(.chooseImage, on: node.id, using: picker)
        #expect(app.alert == nil && app.document.images.isEmpty && !app.isEdited)
    }

    @Test func aNewDocumentWhileTheSavePanelIsOpenWritesNoFile() async throws {
        let hash = ImageHash(of: picture)
        let (app, node) = await imageApp(.embedded(hash))
        app.document.addImage(picture)
        let destination = folder.url.appending(path: "vent.png")
        let picker = InterruptedPicker(answer: destination) { app.newDocument() }
        await app.performImage(.linkImage, on: node.id, using: picker)
        #expect(app.alert == nil && !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }

    @Test func aSecondPressWhileAPanelIsOpenIsIgnored() async throws {
        let (app, node) = await imageApp()
        let file = try folder.write(picture, to: "vent.png")
        let other = try folder.write(AppTestImages.png(level: 200), to: "other.png")
        let second = ScriptedPicker([other])
        let picker = InterruptedPicker(answer: file) {
            await app.performImage(.chooseImage, on: node.id, using: second)
        }
        await app.performImage(.chooseImage, on: node.id, using: picker)
        #expect(second.asked.isEmpty, "the second panel is never opened")
        #expect(app.document.images.count == 1 && app.document.images[ImageHash(of: picture)] == picture)
    }
}

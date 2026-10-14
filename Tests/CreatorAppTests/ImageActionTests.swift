#if canImport(CoreGraphics)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// The Image Field's buttons (fields spec §5): choosing, linking, relinking and embedding a picture through the file panels,
/// the refusals, and the file that results.
@MainActor
struct ImageActionTests {
    let folder = AppTempFolder()
    let picture = AppTestImages.png(level: 100)

    /// An app showing one Image Field, which is an output so that it is evaluated.
    func imageApp(_ setting: ImageReference? = nil) async -> (AppModel, Node) {
        var builder = GraphBuilder()
        let node = builder.add(ImageFieldNode.self)
        var graph = builder.graph
        graph.nodes[node.id]?.isOutput = true
        if let setting { graph.nodes[node.id]?.inputValues[NodeSetting.image] = .image(setting) }
        let app = await makeApp(graph)
        return (app, graph.nodes[node.id] ?? node)
    }

    func setting(_ app: AppModel, _ node: Node) -> ImageReference? {
        if case .image(let reference)? = app.document.graph.nodes[node.id]?.inputValues[NodeSetting.image] { reference } else { nil }
    }

    func state(_ app: AppModel, _ node: Node) async -> NodeState? {
        await app.settle()
        return app.document.results[node.id]?.state
    }

    // MARK: Choose

    @Test func choosingAFileEmbedsItAsOneUndoStepAndTheNodeRuns() async throws {
        let (app, node) = await imageApp()
        let file = try folder.write(picture, to: "vent.png")
        await app.performImage(.chooseImage, on: node.id, using: ScriptedPicker([file]))
        let hash = ImageHash(of: picture)
        #expect(setting(app, node) == .embedded(hash) && app.document.images[hash] == picture)
        #expect(app.isEdited && app.document.undoName == "Choose Image")
        #expect(await state(app, node)?.isSuccess == true)
        app.document.undo()
        #expect(setting(app, node) == nil && !app.isEdited)
    }

    @Test func thePanelIsAskedForPNGAndJPEGOnly() async throws {
        let (app, node) = await imageApp()
        let picker = ScriptedPicker([nil])
        await app.performImage(.chooseImage, on: node.id, using: picker)
        #expect(picker.asked.map(\.types) == [[.png, .jpeg]])
        #expect(app.alert == nil && setting(app, node) == nil, "cancelling changes nothing and says nothing")
    }

    @Test func aFileThatIsNotAUsableImageIsRefusedByNameAndTheSettingIsUnchanged() async throws {
        let (app, node) = await imageApp()
        let text = try folder.write(Data("not a picture".utf8), to: "notes.png")
        await app.performImage(.chooseImage, on: node.id, using: ScriptedPicker([text]))
        #expect(app.alert == .problem(AppProblem("“notes.png” can't be used as an image", ImageProblem.undecodable.message)))
        let gif = try folder.write(AppTestImages.png(type: .gif), to: "loop.gif")
        await app.performImage(.chooseImage, on: node.id, using: ScriptedPicker([gif]))
        #expect(app.alert == .problem(AppProblem("“loop.gif” can't be used as an image", ImageProblem.unsupportedType.message)))
        let wide = try folder.write(AppTestImages.png(8_193, 1), to: "wide.png")
        await app.performImage(.chooseImage, on: node.id, using: ScriptedPicker([wide]))
        #expect(app.alert == .problem(AppProblem("“wide.png” can't be used as an image",
                                                 ImageProblem.tooManyPixels(width: 8_193, height: 1).message)))
        #expect(setting(app, node) == nil && !app.isEdited && app.document.images.isEmpty)
    }

    @Test func aFileOverSixteenMegabytesIsRefusedWithoutBeingEmbedded() async throws {
        let (app, node) = await imageApp()
        let huge = try folder.write(Data(count: ImageLimits.maxBytes + 1), to: "huge.png")
        await app.performImage(.chooseImage, on: node.id, using: ScriptedPicker([huge]))
        #expect(app.alert == .problem(AppProblem("“huge.png” can't be used as an image",
                                                 ImageProblem.tooManyBytes(ImageLimits.maxBytes + 1).message)))
        #expect(setting(app, node) == nil && app.document.images.isEmpty)
    }

    @Test func aFolderOrAMissingFileChosenIsRefusedToo() async throws {
        let (app, node) = await imageApp()
        await app.performImage(.chooseImage, on: node.id, using: ScriptedPicker([folder.url]))
        await app.performImage(.chooseImage, on: node.id, using: ScriptedPicker([folder.url.appending(path: "gone.png")]))
        #expect(app.alert != nil && setting(app, node) == nil)
    }

    // MARK: Link

    @Test func linkingAnEmbeddedPictureSavesItWhereAskedThenLinksItWithoutTouchingAnythingElse() async throws {
        let hash = ImageHash(of: picture)
        let (app, node) = await imageApp(.embedded(hash))
        app.document.addImage(picture)
        let destination = folder.url.appending(path: "maps/vent.png")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let picker = ScriptedPicker([destination])
        await app.performImage(.linkImage, on: node.id, using: picker)
        #expect(try Data(contentsOf: destination) == picture, "the original bytes")
        #expect(picker.asked.first?.name == "image.png")
        #expect(setting(app, node) == .linked(relativePath: nil, absolutePath: destination.standardizedFileURL.path(percentEncoded: false)))
        #expect(app.document.undoName == "Link Image")
        #expect(await state(app, node)?.isSuccess == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path(percentEncoded: false)) == ["maps"])
    }

    @Test func aWriteThatFailsLeavesTheEmbeddedPictureAlone() async throws {
        let hash = ImageHash(of: picture)
        let (app, node) = await imageApp(.embedded(hash))
        app.document.addImage(picture)
        let nowhere = folder.url.appending(path: "no/such/folder/vent.png")
        await app.performImage(.linkImage, on: node.id, using: ScriptedPicker([nowhere]))
        #expect(app.alert?.title == "“vent.png” couldn't be saved" && setting(app, node) == .embedded(hash))
    }

    @Test func withNoPictureLinkingAnExistingFileLinksIt() async throws {
        let (app, node) = await imageApp()
        let file = try folder.write(picture, to: "vent.png")
        await app.performImage(.linkImage, on: node.id, using: ScriptedPicker([file]))
        #expect(setting(app, node) == .linked(relativePath: nil, absolutePath: file.standardizedFileURL.path(percentEncoded: false)))
        #expect(app.document.undoName == "Link Image" && app.document.images.isEmpty, "nothing is copied into the document")
    }

    // MARK: Relink and embed

    @Test func relinkingAMissingFileFixesTheNodeAndOnceSavedRecordsAPathFromTheDocument() async throws {
        let oldPath = folder.url.appending(path: "old/vent.png").path(percentEncoded: false)
        let gone = ImageReference.linked(relativePath: nil, absolutePath: oldPath)
        let (app, node) = await imageApp(gone)
        #expect(await state(app, node) != nil)
        if case .error(let message)? = await state(app, node) {
            #expect(message.hasPrefix("Image 'vent.png' wasn't found at ") && message.hasSuffix("/old/. Relink it in the inspector."))
        } else {
            Issue.record("a missing link must be an error")
        }
        let documentURL = folder.url.appending(path: "doc/Plate.mcgraph")
        try FileManager.default.createDirectory(at: documentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try app.save(to: documentURL)
        let file = try folder.write(picture, to: "doc/maps/vent.png")
        await app.performImage(.relinkImage, on: node.id, using: ScriptedPicker([file]))
        let absolute = file.standardizedFileURL.path(percentEncoded: false)
        #expect(setting(app, node) == .linked(relativePath: "maps/vent.png", absolutePath: absolute))
        #expect(app.document.undoName == "Relink Image")
        #expect(await state(app, node)?.isSuccess == true)
    }

    @Test func embeddingALinkReadsTheFileIntoTheDocumentAndUndoGoesBackToTheLink() async throws {
        let file = try folder.write(picture, to: "vent.png")
        let link = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let (app, node) = await imageApp(link)
        await app.performImage(.embedImage, on: node.id, using: ScriptedPicker([]))
        #expect(setting(app, node) == .embedded(ImageHash(of: picture)) && app.document.images.count == 1)
        #expect(app.document.undoName == "Embed Image")
        app.document.undo()
        #expect(setting(app, node) == link)
    }

    @Test func embeddingALinkWhoseFileIsGoneSaysSoAndChangesNothing() async throws {
        let missing = folder.url.appending(path: "gone.png").path(percentEncoded: false)
        let link = ImageReference.linked(relativePath: nil, absolutePath: missing)
        let (app, node) = await imageApp(link)
        await app.performImage(.embedImage, on: node.id, using: ScriptedPicker([]))
        #expect(app.alert?.message.contains("wasn't found at") == true && setting(app, node) == link)
    }

    // MARK: The buttons reach the app

    @Test func anInspectorButtonPressedInTheEditorReachesTheAppShellAndRunsWithTheWindowsPanels() async throws {
        let (app, node) = await imageApp()
        let file = try folder.write(picture, to: "vent.png")
        app.filePicker = ScriptedPicker([file])
        app.editor.press(.chooseImage, on: node.id)
        let request = try #require(app.editor.inspectorRequest)
        let task = try #require(app.handleImage(request), "with the window's panels the button starts the action")
        await task.value
        #expect(setting(app, node) == .embedded(ImageHash(of: picture)))
    }

    @Test func withoutWindowPanelsTheButtonsStartNothing() async throws {
        let (app, node) = await imageApp()
        app.editor.press(.chooseImage, on: node.id)
        let request = try #require(app.editor.inspectorRequest)
        #expect(app.handleImage(request) == nil, "no task was started, so nothing can happen later either")
        app.handle(request)
        await app.settle()
        #expect(setting(app, node) == nil && app.alert == nil)
    }

    // MARK: The file

    @Test func savedAndReopenedAnEmbeddedPictureComesBackAndAnUnusedOneDoesNot() async throws {
        let (app, node) = await imageApp()
        let chosen = try folder.write(picture, to: "vent.png")
        await app.performImage(.chooseImage, on: node.id, using: ScriptedPicker([chosen]))
        app.document.addImage(AppTestImages.png(level: 7))
        let url = folder.url.appending(path: "Plate.mcgraph")
        try app.save(to: url)
        #expect(!app.isEdited && app.document.documentURL == url)

        let reopened = await makeApp()
        try reopened.open(url)
        await reopened.settle()
        #expect(reopened.document.images == [ImageHash(of: picture): picture], "the unused one was dropped on save")
        #expect(reopened.document.results[node.id]?.state.isSuccess == true)
        #expect(reopened.document.documentURL == url)
    }

    @Test func aDocumentFolderMovedWithItsLinkedPictureStillFindsItThroughTheRelativePath() async throws {
        let (app, node) = await imageApp()
        let original = folder.url.appending(path: "first", directoryHint: .isDirectory)
        let file = try folder.write(picture, to: "first/maps/vent.png")
        await app.performImage(.linkImage, on: node.id, using: ScriptedPicker([file]))
        let url = original.appending(path: "Plate.mcgraph")
        try app.save(to: url)
        let saved = try GraphFileIO.decode(Data(contentsOf: url), registry: app.registry)
        let stored = saved.graph.nodes[node.id]?.inputValues[NodeSetting.image]
        let absolute = file.standardizedFileURL.path(percentEncoded: false)
        #expect(stored == .image(.linked(relativePath: "maps/vent.png", absolutePath: absolute)))

        let moved = folder.url.appending(path: "second", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: original, to: moved)
        let reopened = await makeApp()
        try reopened.open(moved.appending(path: "Plate.mcgraph"))
        await reopened.settle()
        #expect(reopened.document.results[node.id]?.state.isSuccess == true, "the absolute path is stale; the relative one is not")
    }

    /// After Save As into another folder the open document is on the new folder's terms at once, not at the next reopen:
    /// the relative path that was tried first is made again from where the file is, so a same-named picture in the new
    /// folder cannot take its place unseen; and saving is no edit and no undo step.
    @Test func afterSaveAsTheOpenDocumentIgnoresALookAlikePictureInTheNewFolder() async throws {
        let (app, node) = await imageApp()
        let file = try folder.write(picture, to: "first/maps/vent.png")
        await app.performImage(.linkImage, on: node.id, using: ScriptedPicker([file]))
        try app.save(to: folder.url.appending(path: "first/Plate.mcgraph"))
        let lookAlike = try folder.write(AppTestImages.png(level: 200), to: "second/maps/vent.png")
        let steps = app.document.undoName
        try app.save(to: folder.url.appending(path: "second/Plate.mcgraph"))
        let absolute = file.standardizedFileURL.path(percentEncoded: false)
        #expect(setting(app, node) == .linked(relativePath: "../first/maps/vent.png", absolutePath: absolute))
        #expect(app.document.imageResolver.location(of: .linked(relativePath: "../first/maps/vent.png", absolutePath: absolute))
            == file.standardizedFileURL)
        #expect(!app.isEdited && app.document.undoName == steps, "saving is no edit and adds no undo step")
        #expect(try Data(contentsOf: lookAlike) != picture)
        await app.settle()
        let scalar = try #require(app.document.results[node.id]?.outputs?["field"]?.items.first)
        guard case .field(.image(let image, _, _, _, _)) = scalar else {
            Issue.record("the node should make an image field")
            return
        }
        #expect(image.pixels.allSatisfy { $0 == 100 * 257 }, "the picture beside the first folder, not the look-alike")
    }
}
#endif

import CreatorEditor
import CreatorGraph
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Files the system asks the app to open (spec §6.1, §11, gap M6-d): Finder, the Dock, `open -a` and the command line
/// all arrive as `AppModel.openRequested(_:)`, and respect the unsaved-changes question.
@MainActor
struct AppModelOpenURLTests {
    /// A saved graph with one box, at a fresh path the caller removes.
    func boxFile(_ name: String) throws -> URL {
        var builder = GraphBuilder()
        _ = builder.box()
        let url = temporaryURL(name)
        try GraphFileIO.encode(GraphFile(graph: builder.graph)).write(to: url)
        return url
    }

    func edit(_ app: AppModel) throws {
        try app.document.perform(.addNode(BuiltInNodes.registry.makeNode(NumberNode.typeID)))
    }

    @Test func aFileOpensInTheUneditedDocument() async throws {
        let url = try boxFile("dropped.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let app = await makeApp()
        app.openRequested(url)
        await app.settle()
        #expect(app.fileURL == url && app.displayName == url.lastPathComponent)
        #expect(app.document.graph.nodes.count == 3 && !app.isEdited)
        #expect(app.alert == nil)
    }

    @Test func withChangesItAsksFirstAndDiscardOpensTheFile() async throws {
        let url = try boxFile("asked.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let app = await makeApp()
        try edit(app)
        app.openRequested(url)
        #expect(app.alert == .discardChanges)
        #expect(app.fileURL == nil && app.document.graph.nodes.count == 1, "nothing is discarded until the person says so")
        await app.discardChanges()
        #expect(app.fileURL == url && app.document.graph.nodes.count == 3 && !app.isEdited)
    }

    @Test func cancellingKeepsTheDocumentAndForgetsTheFile() async throws {
        let url = try boxFile("cancelled.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let app = await makeApp()
        try edit(app)
        app.openRequested(url)
        app.keepChanges()
        await app.discardChanges()
        #expect(app.fileURL == nil && app.isEdited && app.alert == nil)
    }

    /// Reopening the open file never reloads it, edited or not: a double-click on it just does nothing.
    @Test(arguments: [false, true])
    func theFileThatIsAlreadyOpenIsLeftAlone(_ edited: Bool) async throws {
        let url = try boxFile("same.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let app = await makeApp()
        try app.open(url)
        if edited { try edit(app) }
        let document = app.document
        app.openRequested(url)
        #expect(app.alert == nil && app.isEdited == edited, "reopening would throw the edits away without asking")
        #expect(app.document === document)
    }

    @Test func aTypedButUncommittedValueIsKeptByAskingFirst() async throws {
        let url = try boxFile("typed.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        var builder = GraphBuilder()
        let extrude = builder.solid(distance: 10).extrude
        let app = await makeApp(builder.graph)
        let id = extrude.id
        app.editor.notePendingEntry(PendingEntry(text: "25") { value in
            try? app.document.perform(.setInput(id, "distance", .number(value)))
        })
        app.openRequested(url)
        #expect(app.alert == .discardChanges, "the typed value is a change, as it is when closing")
        #expect(app.document.graph.nodes[id]?.inputValues["distance"] == .number(25))
        #expect(app.fileURL == nil)
    }

    @Test func aURLThatIsNotAFileIsIgnored() async throws {
        let app = await makeApp()
        app.openRequested(try #require(URL(string: "https://example.com/a.mcgraph")))
        #expect(app.alert == nil && app.fileURL == nil)
    }

    @Test func aFileThatCantBeReadShowsWhyAndKeepsTheDocument() async throws {
        let url = temporaryURL("notes.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("hello".utf8).write(to: url)
        let app = await makeApp()
        let document = app.document
        app.openRequested(url)
        #expect(app.alert?.title == "“\(url.lastPathComponent)” couldn't be opened")
        #expect(app.document === document)
    }

    @Test func aMissingFileShowsWhy() async throws {
        let app = await makeApp()
        app.openRequested(URL(filePath: "/no/such/folder/gone.mcgraph"))
        #expect(app.alert?.title == "“gone.mcgraph” couldn't be opened")
    }

    @Test func nothingOpensWhileTheCloseQuestionIsUp() async throws {
        let url = try boxFile("late.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let app = await makeApp()
        try edit(app)
        _ = app.closeRequested()
        app.openRequested(url)
        #expect(app.alert == .saveChanges(name: "Untitled"), "the close question isn't replaced")
        // Nothing was queued behind the close question, so confirming a discard has no file to open.
        await app.discardChanges()
        #expect(app.fileURL == nil)
    }

    @Test func severalFilesInOneDropLeaveTheLastOpen() async throws {
        let first = try boxFile("first.mcgraph")
        let second = try boxFile("second.mcgraph")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let app = await makeApp()
        app.openRequested(first)
        app.openRequested(second)
        #expect(app.fileURL == second)
    }

    /// The command line's path is made absolute against the working directory in `main.swift` (human check AS-7); a
    /// URL that carries a base, as `URL(fileURLWithPath:relativeTo:)` makes, opens the same file.
    @Test func aURLRelativeToADirectoryOpensLikeAnyOtherFile() async throws {
        let url = try boxFile("cli.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let relative = URL(fileURLWithPath: url.lastPathComponent, relativeTo: url.deletingLastPathComponent())
        #expect(relative.relativePath == url.lastPathComponent, "the URL really is relative")
        let app = await makeApp()
        app.openRequested(relative)
        #expect(app.document.graph.nodes.count == 3 && !app.isEdited && app.alert == nil)
        #expect(app.fileURL?.standardizedFileURL.path == url.standardizedFileURL.path)
    }
}

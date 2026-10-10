import CreatorGraph
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// The window's title, edited dot and represented file follow the document (spec §6.1, gap M6-a).
@MainActor
struct WindowChromeTests {
    /// A window's title bar, recording every write.
    final class RecordingChrome: WindowChrome {
        var titleWrites: [String] = []
        var editedWrites: [Bool] = []
        var urlWrites: [URL?] = []
        var title = "MetalCreator" { didSet { titleWrites.append(title) } }
        var isDocumentEdited = false { didSet { editedWrites.append(isDocumentEdited) } }
        var representedURL: URL? { didSet { urlWrites.append(representedURL) } }
    }

    func edit(_ app: AppModel) throws {
        try app.document.perform(.addNode(BuiltInNodes.registry.makeNode(NumberNode.typeID)))
    }

    @Test func anUntitledDocumentShowsItsNameAndNoFile() async {
        let app = await makeApp()
        let chrome = RecordingChrome()
        WindowChromeSync(model: app, chrome: chrome).apply()
        #expect(chrome.title == "Untitled" && !chrome.isDocumentEdited && chrome.representedURL == nil)
    }

    @Test func aSavedDocumentShowsItsFileAndTheEditedDotFollowsTheChanges() async throws {
        let url = temporaryURL("bracket.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let app = await makeApp()
        try app.save(to: url)
        let chrome = RecordingChrome()
        let sync = WindowChromeSync(model: app, chrome: chrome)
        sync.apply()
        #expect(chrome.title == url.lastPathComponent && chrome.representedURL == url && !chrome.isDocumentEdited)
        try edit(app)
        sync.apply()
        #expect(chrome.isDocumentEdited)
        try app.save(to: url)
        sync.apply()
        #expect(!chrome.isDocumentEdited, "saving clears the dot")
    }

    @Test func applyingTwiceWritesNothingTheSecondTime() async throws {
        let app = await makeApp()
        let chrome = RecordingChrome()
        let sync = WindowChromeSync(model: app, chrome: chrome)
        sync.apply()
        let writes = (chrome.titleWrites.count, chrome.editedWrites.count, chrome.urlWrites.count)
        sync.apply()
        #expect((chrome.titleWrites.count, chrome.editedWrites.count, chrome.urlWrites.count) == writes)
    }

    @Test func newClearsTheFileAndTheDot() async throws {
        let url = temporaryURL("a.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let app = await makeApp()
        try app.save(to: url)
        try edit(app)
        let chrome = RecordingChrome()
        let sync = WindowChromeSync(model: app, chrome: chrome)
        sync.apply()
        app.newDocument()
        await app.discardChanges()
        sync.apply()
        #expect(chrome.title == "Untitled" && chrome.representedURL == nil && !chrome.isDocumentEdited)
    }

    /// `follow()` pushes by itself: a change to the document reaches the window without anyone calling `apply()`.
    @Test func followingPushesChangesAsTheyHappen() async throws {
        let app = await makeApp()
        let chrome = RecordingChrome()
        let task = Task { await WindowChromeSync(model: app, chrome: chrome).follow() }
        defer { task.cancel() }
        try await until { chrome.title == "Untitled" }
        try edit(app)
        try await until { chrome.isDocumentEdited }
        let url = temporaryURL("followed.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        try await until { !chrome.isDocumentEdited && chrome.title == url.lastPathComponent }
        #expect(chrome.representedURL == url)
    }

    /// Lets the main actor run until `condition` holds, or fails after five seconds (it returns as soon as the condition holds).
    func until(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("the window never caught up", sourceLocation: sourceLocation)
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

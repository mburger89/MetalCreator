import CreatorEditor
import CreatorGraph
import CreatorNodes
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// Closing the window and quitting with unsaved changes (spec §6.1, gap M6-b): the alert, each answer, and the one
/// reply the window gets. MetalUI's window and app are not built here (no public headless window, gap M6-e), so the
/// model's handler and reply are driven directly.
@MainActor
struct AppModelCloseTests {
    /// An app whose window replies are recorded.
    final class Replies {
        var values: [Bool] = []
    }

    func makeEditedApp(file: URL? = nil, picker: ScriptedPicker? = nil) async throws -> (AppModel, Replies) {
        let app = await makeApp()
        let replies = Replies()
        app.replyToCloseRequest = { replies.values.append($0) }
        app.filePicker = picker
        if let file { try app.save(to: file) }
        try app.document.perform(.addNode(BuiltInNodes.registry.makeNode(NumberNode.typeID)))
        #expect(app.isEdited)
        return (app, replies)
    }

    @Test func aDocumentWithoutChangesClosesAtOnceWithNoAlert() async {
        let app = await makeApp()
        #expect(app.closeRequested() == .now)
        #expect(app.alert == nil && app.closeRequest == .idle)
    }

    @Test func aDocumentWithChangesAsksAndTheWindowWaits() async throws {
        let (app, replies) = try await makeEditedApp()
        #expect(app.closeRequested() == .later)
        #expect(app.alert == .saveChanges(name: "Untitled"))
        #expect(app.alert?.title == "Do you want to save the changes to “Untitled”?")
        #expect(app.closeRequest == .asking)
        #expect(replies.values.isEmpty, "nothing is answered until the person answers")
    }

    @Test func theAlertNamesTheFile() async throws {
        let url = temporaryURL("bracket.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let (app, _) = try await makeEditedApp(file: url)
        _ = app.closeRequested()
        #expect(app.alert == .saveChanges(name: url.lastPathComponent))
    }

    @Test func aTypedButUncommittedValueCountsAsAChange() async throws {
        var builder = GraphBuilder()
        let extrude = builder.solid(distance: 10).extrude
        let app = await makeApp(builder.graph)
        let id = extrude.id
        app.editor.notePendingEntry(PendingEntry(text: "25") { value in
            try? app.document.perform(.setInput(id, "distance", .number(value)))
        })
        #expect(!app.isEdited, "typed, not committed")
        #expect(app.closeRequested() == .later, "closing commits the typed value, which is a change")
        #expect(app.document.graph.nodes[id]?.inputValues["distance"] == .number(25))
    }

    @Test func aSecondRequestWhileAskingKeepsTheFirstAlert() async throws {
        let (app, _) = try await makeEditedApp()
        _ = app.closeRequested()
        #expect(app.closeRequested() == .later)
        #expect(app.closeRequest == .asking && app.alert == .saveChanges(name: "Untitled"))
    }

    @Test func aRequestAfterAnotherAlertTookItsPlaceAsksAgain() async throws {
        let (app, replies) = try await makeEditedApp()
        _ = app.closeRequested()
        app.alert = .problem(AppProblem("Something else failed", "It happened while the question was up."))
        #expect(app.closeRequested() == .later)
        #expect(app.alert == .saveChanges(name: "Untitled"), "without its buttons nothing could answer the close request")
        #expect(app.closeRequest == .asking)
        await app.answerSaveChanges(.dontSave)
        #expect(replies.values == [true])
    }

    @Test func saveWritesTheDocumentsFileThenClosesTheWindow() async throws {
        let url = temporaryURL("saved.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let picker = ScriptedPicker([])
        let (app, replies) = try await makeEditedApp(file: url, picker: picker)
        _ = app.closeRequested()
        await app.answerSaveChanges(.save)
        #expect(replies.values == [true])
        #expect(!app.isEdited && app.alert == nil && app.closeRequest == .idle)
        #expect(picker.asked.isEmpty, "a titled document saves without a panel")
        let saved = try GraphFileIO.decode(Data(contentsOf: url), registry: BuiltInNodes.registry)
        #expect(saved.graph.nodes.count == 1)
    }

    @Test func saveOfAnUntitledDocumentRunsSaveAsAndClosesOnceItIsWritten() async throws {
        let url = temporaryURL("new.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let picker = ScriptedPicker([url])
        let (app, replies) = try await makeEditedApp(picker: picker)
        _ = app.closeRequested()
        await app.answerSaveChanges(.save)
        #expect(picker.asked.map(\.name) == ["Untitled.mcgraph"])
        #expect(replies.values == [true])
        #expect(app.fileURL == url && !app.isEdited)
    }

    @Test func aCancelledSaveAsKeepsTheWindowAndTheChanges() async throws {
        let (app, replies) = try await makeEditedApp(picker: ScriptedPicker([nil]))
        _ = app.closeRequested()
        await app.answerSaveChanges(.save)
        #expect(replies.values == [false])
        #expect(app.isEdited && app.fileURL == nil && app.closeRequest == .idle)
    }

    @Test func aFailedSaveKeepsTheWindowAndShowsWhy() async throws {
        let missing = URL.temporaryDirectory.appending(path: "\(UUID().uuidString)/no/such/folder/x.mcgraph")
        let (app, replies) = try await makeEditedApp(picker: ScriptedPicker([missing]))
        _ = app.closeRequested()
        await app.answerSaveChanges(.save)
        #expect(replies.values == [false])
        #expect(app.isEdited)
        #expect(app.alert?.title == "“x.mcgraph” couldn't be saved")
    }

    @Test func dontSaveClosesAndLeavesTheFileAlone() async throws {
        let url = temporaryURL("kept.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let (app, replies) = try await makeEditedApp(file: url)
        let before = try Data(contentsOf: url)
        _ = app.closeRequested()
        await app.answerSaveChanges(.dontSave)
        #expect(replies.values == [true])
        #expect(try Data(contentsOf: url) == before)
        #expect(app.alert == nil && app.closeRequest == .idle)
    }

    @Test func cancelKeepsTheWindowAndAskingAgainIsPossible() async throws {
        let (app, replies) = try await makeEditedApp()
        _ = app.closeRequested()
        await app.answerSaveChanges(.cancel)
        #expect(replies.values == [false])
        #expect(app.isEdited && app.alert == nil && app.closeRequest == .idle)
        #expect(app.closeRequested() == .later, "a later close asks again")
        #expect(app.alert == .saveChanges(name: "Untitled"))
    }

    @Test func aRepeatedAnswerRepliesOnlyOnce() async throws {
        let (app, replies) = try await makeEditedApp()
        _ = app.closeRequested()
        await app.answerSaveChanges(.dontSave)
        await app.answerSaveChanges(.dontSave)
        await app.answerSaveChanges(.cancel)
        #expect(replies.values == [true])
    }

    @Test func anAnswerWithNoQuestionDoesNothing() async throws {
        let (app, replies) = try await makeEditedApp()
        await app.answerSaveChanges(.dontSave)
        #expect(replies.values.isEmpty)
    }

    @Test func newAndOpenWaitWhileTheCloseQuestionIsUp() async throws {
        let picker = ScriptedPicker([])
        let (app, _) = try await makeEditedApp(picker: picker)
        _ = app.closeRequested()
        let document = app.document
        app.newDocument()
        await app.openDocument(using: picker)
        #expect(app.alert == .saveChanges(name: "Untitled"), "the close question isn't replaced")
        #expect(app.document === document && picker.asked.isEmpty)
    }

    @Test func theCloseQuestionReplacesTheDiscardQuestion() async throws {
        let (app, _) = try await makeEditedApp()
        app.newDocument()
        #expect(app.alert == .discardChanges)
        _ = app.closeRequested()
        #expect(app.alert == .saveChanges(name: "Untitled"))
        await app.discardChanges()
        #expect(app.isEdited, "the replaced New is forgotten")
    }
}

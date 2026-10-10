import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Inputs the groups spec implies for the levels of the graph panel (§6), pinned: two instances of one definition, a
/// value typed before entering, an Output node added inside, a drag under way, and a saved file.
@MainActor
struct EditorLevelReviewTests {
    /// The rectangle's profile in a result.
    func profile(_ result: NodeResult?) -> Profile2D? {
        for case .profile(let profile)? in [result?.outputs?["profile"]?.items.first] { return profile }
        return nil
    }

    @Test func insideASharedDefinitionTheStatesAreTheEnteredInstances() async throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.perform(.duplicate)
        let second = try #require(editor.selection.first)
        try editor.edit(.setInput(second, "width", .number(50)), name: UndoName.changeInput("Width"))
        try editor.edit(.setInput(grouped.number.id, "value", .number(7)), name: UndoName.changeInput("Value"))
        await editor.document.waitForEvaluation()

        editor.enterGroup(grouped.group)
        await editor.document.waitForEvaluation()
        let first = try #require(editor.result(of: grouped.rectangle.id))
        editor.exitGroup()
        editor.enterGroup(second)
        await editor.document.waitForEvaluation()
        let other = try #require(editor.result(of: grouped.rectangle.id))
        #expect(first.state.isSuccess && other.state.isSuccess)
        #expect(profile(first) != nil && profile(first) != profile(other), "the first is wired to 7 mm, the second typed 50")
        #expect(profile(editor.document.innerResults[[second, grouped.rectangle.id]]) == profile(other))
    }

    @Test func aValueTypedBeforeEnteringIsCommittedToTheNodeItWasTypedOn() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.number.id]
        guard case .slider(let field, _)? = editor.inspectorPage.sections.first?.rows.first else {
            Issue.record("no value slider on the Number node")
            return
        }
        editor.notePendingEntry(PendingEntry(text: "33", commit: { editor.setNumber(field, to: $0) }))
        editor.selection = [grouped.group]
        editor.enterGroup(grouped.group)
        #expect(editor.rootGraph.nodes[grouped.number.id]?.inputValues["value"] == .number(33))
        #expect(grouped.current?.graph.nodes[grouped.number.id] == nil, "and not looked for inside")
    }

    @Test func anOutputNodeAddedInsideAGroupIsRefusedWithTheSpecsSentence() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        #expect(!editor.addNode(OutputTestNode.typeID, atScreen: Vector2(100, 100)))
        #expect(editor.refusal?.message == "An Output node can't go in a group.")
        #expect(editor.graph.nodes.count == 4)
        #expect(editor.addNode(NumberTestNode.typeID, atScreen: Vector2(100, 100)), "any other node goes in")
        #expect(grouped.current?.graph.nodes.count == 5)
    }

    @Test func theLevelDoesntChangeUnderADragInProgress() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        let start = editor.screenPoint(in: grouped.group)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(40, 0))
        #expect(editor.interaction != nil)
        #expect(!editor.enterGroup(grouped.group))
        #expect(editor.perform(.enterGroup), "claimed, so the key can't go elsewhere mid-drag")
        #expect(editor.levelPath.isEmpty)
        editor.pointerReleased(from: start, at: start + Vector2(40, 0))
        #expect(editor.enterGroup(grouped.group))
    }

    @Test func theLevelShownIsNotSavedWithTheFile() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let reopened = EditorModel(document: try DocumentModel(data: try editor.document.fileData(),
                                                               registry: editorTestRegistry, kernel: FakeKernel()))
        #expect(reopened.levelPath.isEmpty && reopened.graph.nodes.count == 3)
        #expect(reopened.document.definitions == editor.document.definitions)
        #expect(reopened.document.inspectedLevel.isEmpty)
    }
}

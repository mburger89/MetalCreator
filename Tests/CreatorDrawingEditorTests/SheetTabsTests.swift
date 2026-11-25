import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The sheet tabs, driven through a headless window the way the graph panel's window tests click (plan R22).
@MainActor
@Suite("Sheet tabs")
struct SheetTabsTests {
    struct Fixture {
        var harness: EditorHarness
        var window: DrawingWindow
        var first: SheetID
        var second: SheetID
    }

    private func open() async throws -> Fixture {
        let one = DrawingSheet(name: "Sheet 1"), two = DrawingSheet(name: "Sheet 2")
        let harness = EditorHarness(document: EditorDocuments.document([one, two]), sheet: one.id)
        let window = try await DrawingWindow.open(size: Size(width: Pixels(600), height: Pixels(100)), scaleFactor: 2) {
            SheetTabs(model: harness.model)
        }
        return Fixture(harness: harness, window: window, first: one.id, second: two.id)
    }

    private func centre(_ f: Fixture, _ label: String) throws -> Point<Pixels> {
        let element = try f.window.window.element(label: label)
        return Point(
            x: element.frame.origin.x + element.frame.size.width / 2, y: element.frame.origin.y + element.frame.size.height / 2)
    }

    @Test func aClickSelectsATab() async throws {
        let f = try await open()
        f.window.window.click(at: try centre(f, "Sheet 2"))
        #expect(f.harness.model.currentSheet == f.second)
        #expect(f.harness.log.commits.isEmpty, "showing a sheet is not an edit")
        #expect(f.harness.log.sheets == [f.second])
    }

    @Test func plusAddsASheet() async throws {
        let f = try await open()
        f.window.window.click(at: try centre(f, "Add Sheet"))
        #expect(f.harness.model.document.sheets.map(\.name) == ["Sheet 1", "Sheet 2", "Sheet 3"])
        #expect(f.harness.model.currentSheet == f.harness.model.document.sheets.last?.id)
        #expect(f.harness.log.commits.map(\.name) == ["Add Sheet"])
    }

    @Test func aDoubleClickRenamesInPlace() async throws {
        let f = try await open()
        f.window.window.doubleClick(at: try centre(f, "Sheet 1"))
        try await f.window.window.runUntilIdle()
        let rename = try #require(f.harness.model.renaming)
        #expect(rename.sheet == f.first && rename.draft == "Sheet 1")
        // The field opens with the whole name selected.
        #expect(rename.selection == TextSelection(range: rename.draft.startIndex..<rename.draft.endIndex))
        #expect(try f.window.window.focusedElement != nil, "the field has focus")
        f.window.window.typeText("Plate")
        f.window.window.typeKey(.return)
        try await f.window.window.runUntilIdle()
        #expect(f.harness.model.renaming == nil)
        #expect(f.harness.model.document.sheets[0].name == "Plate", "typing replaced the selected name")
        #expect(f.harness.log.commits.map(\.name) == ["Rename Sheet"])
    }

    @Test func escapeLeavesTheNameAlone() async throws {
        let f = try await open()
        f.window.window.doubleClick(at: try centre(f, "Sheet 1"))
        try await f.window.window.runUntilIdle()
        f.window.window.typeText("Plate")
        f.window.window.typeKey(.escape)
        try await f.window.window.runUntilIdle()
        #expect(f.harness.model.renaming == nil)
        #expect(f.harness.model.document.sheets[0].name == "Sheet 1")
        #expect(f.harness.log.commits.isEmpty)
    }

    @Test func theMenuHasItsFiveItems() async throws {
        let f = try await open()
        f.window.window.rightClick(at: try centre(f, "Sheet 1"))
        let first = try #require(f.window.window.presentedMenu)
        #expect(first.items.map(\.title) == ["Rename", "Duplicate", "Delete", "Move Left", "Move Right"])
        #expect(first.items.map(\.isEnabled) == [true, true, true, false, true], "the first tab can't move left")
        try f.window.window.dismissMenu()
        f.window.window.rightClick(at: try centre(f, "Sheet 2"))
        let last = try #require(f.window.window.presentedMenu)
        #expect(last.items.map(\.isEnabled) == [true, true, true, true, false], "the last tab can't move right")
        try f.window.window.dismissMenu()
    }

    @Test func duplicateAndMoveRightEachMakeOneCommit() async throws {
        let f = try await open()
        f.window.window.rightClick(at: try centre(f, "Sheet 1"))
        try f.window.window.chooseMenuItem("Move Right")
        #expect(f.harness.log.commits.map(\.name) == ["Move Sheet"])
        #expect(f.harness.model.document.sheets.map(\.name) == ["Sheet 2", "Sheet 1"])
        try await f.window.window.runUntilIdle()
        f.window.window.rightClick(at: try centre(f, "Sheet 2"))
        try f.window.window.chooseMenuItem("Duplicate")
        #expect(f.harness.log.commits.map(\.name) == ["Move Sheet", "Duplicate Sheet"])
        #expect(f.harness.model.document.sheets.count == 3)
    }
}

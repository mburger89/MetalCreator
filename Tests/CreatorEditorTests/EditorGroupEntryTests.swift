import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Entering a group by ⌘↓, a double click and "Edit Group", leaving by ⌘↑, and the group commands inside a level
/// (groups spec §6).
@MainActor
struct EditorGroupEntryTests {
    func key(_ characters: String, _ modifiers: Modifiers) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
    }

    @Test func commandDownAndUpAreTheEnterAndExitKeys() {
        #expect(GraphKeyBindings.command(for: key("\u{f701}", .primary), paletteOpen: false) == .enterGroup)
        #expect(GraphKeyBindings.command(for: key("\u{f700}", .primary), paletteOpen: false) == .exitGroup)
        #expect(GraphKeyBindings.command(for: key("\u{f701}", [.primary, .shift]), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("\u{f701}", .primary), paletteOpen: true) == nil)
        #expect(GraphKeyBindings.command(for: key("\u{f701}", []), paletteOpen: false) == .nudge(Vector2(0, 1), isRepeat: false),
                "a plain arrow still nudges")
    }

    @Test func commandDownEntersTheSelectedGroupNodeAndCommandUpLeaves() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.clearSelection()
        #expect(!editor.perform(.enterGroup), "nothing selected: the key goes on")
        editor.selection = [grouped.number.id]
        #expect(!editor.perform(.enterGroup), "not a group node")
        editor.selection = [grouped.group]
        #expect(editor.perform(.enterGroup))
        #expect(editor.levelPath == [grouped.group])
        #expect(editor.perform(.exitGroup))
        #expect(editor.levelPath.isEmpty)
        #expect(!editor.perform(.exitGroup), "nothing to leave on the top level")
    }

    @Test func theEnterAndExitKeysWaitForAVisiblePanel() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.setDock(.hidden)
        #expect(!editor.perform(.enterGroup))
        editor.setDock(.bottom)
        editor.enterGroup(grouped.group)
        editor.setDock(.hidden)
        #expect(!editor.perform(.exitGroup))
        #expect(editor.levelPath == [grouped.group])
    }

    @Test func aDoubleClickOnAGroupNodeEntersItAndSelectsNothingInside() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let point = editor.screenPoint(in: grouped.group)
        editor.click(point)
        #expect(editor.levelPath.isEmpty && editor.selection == [grouped.group], "one click only selects")
        editor.click(point + Vector2(2, 1), clickCount: 2)
        #expect(editor.levelPath == [grouped.group])
        #expect(editor.selection.isEmpty, "the click that entered didn't select the group node in its own inside")
    }

    /// A slow or wandering pair is one the platform counts 1 and 1, whatever the user's speed setting is.
    @Test func aSlowOrWanderingDoubleClickDoesNotEnter() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let point = editor.screenPoint(in: grouped.group)
        editor.click(point)
        editor.click(point)
        editor.click(point + Vector2(8, 0))
        #expect(editor.levelPath.isEmpty)
    }

    @Test func theInspectorButtonsEnterMakeUniqueAndUngroup() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        let rows = try #require(editor.inspectorPage.sections.first { $0.title == "Group" }?.rows)
        #expect(rows == [
            .button(title: "Edit Group", action: .editGroup), .button(title: "Make Unique", action: .makeUnique),
            .button(title: "Ungroup", action: .ungroup),
        ])
        editor.press(.makeUnique, on: grouped.group)
        #expect(editor.document.definitions.count == 2)
        #expect(editor.graph.nodes[grouped.group]?.name == "Group 2")
        editor.press(.editGroup, on: grouped.group)
        #expect(editor.levelPath == [grouped.group])
        #expect(editor.document.definitions[grouped.definition.id] != nil)
        editor.exitGroup()
        editor.press(.ungroup, on: grouped.group)
        #expect(editor.graph.nodes.count == 4 && editor.graph.nodes[grouped.group] == nil)
        #expect(editor.inspectorRequest == nil, "the panel carried these out itself")
    }

    @Test func groupAndUngroupWorkOnTheLevelShown() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.extrude.id]
        editor.groupSelection()
        let inner = try #require(editor.selection.first)
        #expect(editor.graph.nodes[inner]?.typeID == GroupNodes.groupTypeID)
        #expect(editor.graph.nodes[grouped.extrude.id] == nil)
        #expect(editor.rootGraph.nodes.count == 3, "the top level was not touched")
        editor.ungroupSelection()
        #expect(editor.graph.nodes.count == 4 && editor.document.definitions.count == 1)
        editor.perform(.undo)
        #expect(editor.graph.nodes[inner]?.typeID == GroupNodes.groupTypeID, "undo is one step per command")
    }

    @Test func undoingTheGroupFromInsideLeavesTheGroup() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.perform(.undo)
        #expect(editor.enteredGroups.isEmpty && editor.graph.nodes.count == 4)
        editor.perform(.redo)
        #expect(editor.levelPath.isEmpty && editor.graph.nodes[grouped.group] != nil, "redo doesn't pull the panel back in")
    }
}

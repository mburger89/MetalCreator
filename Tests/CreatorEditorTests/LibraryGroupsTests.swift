import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorEditor

/// The node library's "Groups" section (groups spec §6): the document's definitions, placed by a click or a drag, and
/// deleted when nothing uses them.
@MainActor
struct LibraryGroupsTests {
    func placed(_ editor: EditorModel) -> EditorModel {
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        return editor
    }

    @Test func theSectionListsTheDocumentsDefinitionsByNameWithHowOftenEachIsUsed() throws {
        let plain = makeEditor([])
        #expect(plain.libraryGroups.isEmpty)
        #expect(!plain.libraryItems.contains { $0.isGroupsHeader }, "no definitions, no section")
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let entry = try #require(editor.libraryGroups.first)
        #expect(editor.libraryGroups.count == 1 && entry.name == "Group" && entry.uses == 1 && !entry.canDelete)
        #expect(entry.accent == .purple && entry.key == "group:" + grouped.definition.id.rawValue.uuidString)
        editor.renameGroup(grouped.definition.id, to: "Rib")
        editor.selection = [grouped.group]
        editor.perform(.duplicate)
        editor.press(.makeUnique, on: try #require(editor.selection.first))
        #expect(editor.libraryGroups.map(\.name) == ["Rib", "Rib 2"])
        #expect(editor.libraryGroups.map(\.uses) == [1, 1], "the copy made unique took one instance with it")
    }

    @Test func theRowsEndWithTheGroupsHeaderThenOneRowPerDefinition() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let items = editor.libraryItems
        let tail = items.suffix(2)
        #expect(tail.first?.isGroupsHeader == true && tail.first?.id == "header.groups")
        #expect(tail.last?.group?.group == grouped.definition.id && tail.last?.id == editor.libraryGroups.first?.key)
        #expect(items.dropLast(2).allSatisfy { $0.group == nil && !$0.isGroupsHeader }, "the node types come first")
    }

    @Test func theLibrarySearchFiltersGroupsToo() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.setLibraryQuery("grou")
        #expect(editor.libraryGroups.count == 1)
        #expect(editor.libraryItems.last?.group != nil)
        editor.setLibraryQuery("zzz")
        #expect(editor.libraryGroups.isEmpty && editor.libraryItems.isEmpty)
    }

    @Test func aClickPlacesAnotherInstanceAsOneStep() throws {
        let grouped = try GroupedEditor()
        let editor = placed(grouped.editor)
        let key = try #require(editor.libraryGroups.first).key
        let start = Vector2(100, 400)
        #expect(editor.endLibraryDrag(key, from: start, at: start))
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(added.typeID == GroupNodes.groupTypeID && added.id != grouped.group)
        #expect(added.inputValues[NodeSetting.group] == .group(grouped.definition.id))
        #expect(added.name == "Group")
        #expect(editor.document.definitions.count == 1 && editor.libraryGroups.first?.uses == 2)
        editor.document.undo()
        #expect(editor.graph.nodes[added.id] == nil)
    }

    @Test func aDragPlacesItWhereItIsDropped() throws {
        let grouped = try GroupedEditor()
        let editor = placed(grouped.editor)
        let key = try #require(editor.libraryGroups.first).key
        let canvas = try #require(editor.canvasFrameInWindow)
        let start = canvas.origin + Vector2(-100, 40), end = canvas.origin + Vector2(300, 80)
        editor.moveLibraryDrag(key, from: start, to: end)
        let ghost = try #require(editor.libraryDragEntry)
        #expect(ghost.displayName == "Group" && ghost.accent == .purple)
        #expect(editor.endLibraryDrag(key, from: start, at: end))
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(editor.transform.toScreen(editor.frame(of: added).origin) == Vector2(300, 80))
    }

    @Test func aDefinitionThatIsGoneOrNotYoursPlacesNothing() throws {
        let grouped = try GroupedEditor()
        let editor = placed(grouped.editor)
        let key = "group:" + UUID().uuidString
        #expect(!editor.addFromLibrary(key) && !editor.dropFromLibrary(key, atScreen: Vector2(50, 50)))
        #expect(editor.libraryDragEntry == nil && editor.librarySummary(of: key) == nil)
        #expect(!editor.addFromLibrary("group:not-a-uuid"))
        #expect(editor.graph.nodes.count == 3)
    }

    /// The palette and the drop both end in `addNode(_:atScreen:)`; a key that names nothing registered, or a definition
    /// that is gone, adds no node (not a "missing" node of that type) and says so.
    @Test func addingAStaleOrUnknownKeyAddsNothingAndSaysSo() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let before = editor.document.content
        #expect(!editor.addNode("group:" + UUID().uuidString, atScreen: Vector2(50, 50)))
        #expect(editor.refusal?.message == "That node isn't in the library any more.")
        editor.clearRefusal()
        #expect(!editor.addNode("no.such.type", atScreen: Vector2(50, 50)))
        #expect(editor.refusal?.message == "That node isn't in the library any more.")
        #expect(editor.document.content == before)
        #expect(editor.addNode(NumberTestNode.typeID, atScreen: Vector2(50, 50)), "a registered type still goes in")
    }

    @Test func aGroupCantBePlacedInsideItself() throws {
        let grouped = try GroupedEditor()
        let editor = placed(grouped.editor)
        let key = try #require(editor.libraryGroups.first).key
        editor.enterGroup(grouped.group)
        let before = editor.document.content
        #expect(!editor.addFromLibrary(key))
        #expect(editor.refusal?.message == "A group can't contain itself.")
        #expect(editor.document.content == before)
    }

    @Test func aGroupCanBePlacedInsideAnotherOne() throws {
        let grouped = try GroupedEditor()
        let editor = placed(grouped.editor)
        editor.selection = [grouped.group]
        editor.perform(.duplicate)
        editor.press(.makeUnique, on: try #require(editor.selection.first))
        let other = try #require(editor.document.definitions.values.first { $0.id != grouped.definition.id })
        editor.enterGroup(try #require(editor.selection.first))
        #expect(editor.addFromLibrary(GroupLibraryEntry.key(for: grouped.definition.id)))
        #expect(editor.graph.nodes.values.contains { $0.inputValues[NodeSetting.group] == .group(grouped.definition.id) })
        #expect(editor.document.definitions[other.id] != nil)
    }

    @Test func onlyADefinitionNothingUsesOffersDelete() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        #expect(editor.libraryGroups.first?.canDelete == false)
        editor.selection = [grouped.group]
        editor.deleteSelection()
        let entry = try #require(editor.libraryGroups.first)
        #expect(entry.uses == 0 && entry.canDelete)
        editor.deleteGroup(entry.group)
        #expect(editor.libraryGroups.isEmpty)
        editor.perform(.undo)
        #expect(editor.libraryGroups.count == 1)
    }

    @Test func hoverHelpNamesAGroupsInputsThenOutputs() throws {
        let grouped = try GroupedEditor()
        let key = try #require(grouped.editor.libraryGroups.first).key
        #expect(grouped.editor.librarySummary(of: key) == "Group: width → solid")
    }

    @Test func theLibraryDrawsTheGroupsSection() throws {
        let plain = makeEditor([])
        let withoutGroups = renderHeadless { NodeLibraryView(model: plain, input: GraphPanelInput(model: plain)) }.glyphs.count
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let withGroups = renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) }.glyphs.count
        #expect(withGroups > withoutGroups, "the Groups header and the row")
        editor.setLibraryQuery("zzzz")
        let noMatch = renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) }.glyphs.count
        editor.setLibraryQuery("grou")
        let onlyGroups = renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) }.glyphs.count
        #expect(onlyGroups < withGroups && onlyGroups != noMatch, "the search drops the node types and keeps the Groups section")
        #expect(editor.librarySections.isEmpty && editor.libraryGroups.map(\.name) == ["Group"], "what the view was handed")
        editor.setLibraryQuery("zzzz")
        #expect(editor.librarySections.isEmpty && editor.libraryGroups.isEmpty)
    }
}

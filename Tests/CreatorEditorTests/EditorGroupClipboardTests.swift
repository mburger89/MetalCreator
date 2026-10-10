import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The clipboard carries the definitions copied group nodes use, merged by content on paste (groups spec §9), and
/// never Group Input or Group Output.
@MainActor
struct EditorGroupClipboardTests {
    @Test func copyingAGroupNodeCarriesItsDefinition() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        #expect(editor.clipboard?.definitions == [grouped.definition.id: grouped.definition])
        editor.selection = [grouped.number.id]
        editor.copySelection()
        #expect(editor.clipboard?.definitions.isEmpty == true, "a number needs no definition")
    }

    @Test func pastingNextToItsDefinitionPlacesAnotherInstanceAndAddsNothing() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        editor.paste()
        let copy = try #require(editor.selection.first)
        #expect(copy != grouped.group)
        #expect(editor.document.definitions.count == 1, "same content: merged")
        #expect(editor.graph.nodes[copy]?.inputValues[NodeSetting.group] == .group(grouped.definition.id))
    }

    @Test func aDefinitionTheDocumentLostComesBackWithThePaste() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        editor.ungroupSelection()
        #expect(editor.document.definitions.isEmpty)
        editor.paste()
        let copy = try #require(editor.selection.first)
        #expect(editor.document.definitions[grouped.definition.id] == grouped.definition, "added as it was")
        #expect(editor.graph.nodes[copy]?.typeID == GroupNodes.groupTypeID)
        editor.perform(.undo)
        #expect(editor.document.definitions.isEmpty && editor.graph.nodes[copy] == nil, "the paste is one undo step")
    }

    @Test func aDefinitionEditedSinceTheCopyComesInBesideTheEditedOne() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        editor.enterGroup(grouped.group)
        let start = editor.screenPoint(in: grouped.rectangle.id, inset: Vector2(84, 100))
        editor.drag(start, start + Vector2(40, 0))
        editor.exitGroup()
        editor.paste()
        let copy = try #require(editor.selection.first)
        #expect(editor.document.definitions.count == 2)
        let copied = try #require(editor.graph.nodes[copy])
        let imported = try #require(editor.registry.group(of: copied))
        #expect(imported.id != grouped.definition.id && imported.name == "Group (imported)")
        #expect(imported.graph.nodes[grouped.rectangle.id]?.position
                == grouped.definition.graph.nodes[grouped.rectangle.id]?.position, "the copy is the definition as it was copied")
        #expect(grouped.current?.graph.nodes[grouped.rectangle.id]?.position
                != grouped.definition.graph.nodes[grouped.rectangle.id]?.position, "and the edit stayed in the original")
        #expect(editor.graph.nodes[grouped.group]?.inputValues[NodeSetting.group] == .group(grouped.definition.id),
                "the node already there still uses the edited one")
    }

    @Test func pastingTheSameStaleCopyTwiceAddsItsDefinitionOnce() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        editor.enterGroup(grouped.group)
        let start = editor.screenPoint(in: grouped.rectangle.id, inset: Vector2(84, 100))
        editor.drag(start, start + Vector2(40, 0))
        editor.exitGroup()
        editor.paste()
        let first = try #require(editor.selection.first)
        editor.paste()
        let second = try #require(editor.selection.first)
        #expect(first != second && editor.document.definitions.count == 2, "the second paste reuses the first one's copy")
        let imported = editor.graph.nodes[first]?.inputValues[NodeSetting.group]
        #expect(imported != .group(grouped.definition.id) && editor.graph.nodes[second]?.inputValues[NodeSetting.group] == imported)
        editor.perform(.undo)
        #expect(editor.document.definitions.count == 2 && editor.graph.nodes[second] == nil, "undo takes back the second node only")
    }

    @Test func renamingTheDefinitionAfterCopyingDoesNotMakeThePasteACopy() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        try editor.document.perform(GroupCommands.rename(grouped.definition.id, to: "Rib", in: editor.document.content))
        editor.paste()
        let copy = try #require(editor.selection.first)
        #expect(editor.document.definitions.count == 1, "only the name changed")
        #expect(editor.graph.nodes[copy]?.inputValues[NodeSetting.group] == .group(grouped.definition.id))
    }

    @Test func nestedDefinitionsTravelAndMerge() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.rectangle.id]
        editor.groupSelection()
        editor.exitGroup()
        editor.selection = [grouped.group]
        editor.copySelection()
        #expect(editor.clipboard?.definitions.count == 2, "the group and the group inside it")
        editor.paste()
        #expect(editor.document.definitions.count == 2)
    }

    @Test func groupInputAndOutputAreNeverCopiedDuplicatedOrDeleted() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selectAll()
        editor.copySelection()
        #expect(editor.clipboard?.nodes.map(\.id).sorted() == [grouped.rectangle.id, grouped.extrude.id].sorted())
        editor.paste()
        #expect(editor.graph.nodes.count == 6, "two nodes pasted, not the boundary")
        #expect(editor.graph.nodes.values.filter(GroupNodes.isBoundary).count == 2)
        editor.selectAll()
        editor.deleteSelection()
        #expect(editor.graph.nodes.values.allSatisfy(GroupNodes.isBoundary) && editor.graph.nodes.count == 2)
        editor.perform(.undo)
        #expect(editor.graph.nodes.count == 6, "the delete was one step")
    }

    /// Copying only Group Input and Group Output copies nothing, so it leaves the clipboard as it was: a paste still
    /// pastes what was copied before.
    @Test func copyingOnlyTheBoundaryKeepsTheEarlierClipboard() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.rectangle.id]
        editor.copySelection()
        let earlier = editor.clipboard
        editor.selection = Set(editor.graph.nodes.values.filter(GroupNodes.isBoundary).map(\.id))
        editor.copySelection()
        #expect(editor.clipboard == earlier)
    }

    /// Cut deletes first and copies only what the delete took, so a cut that deletes nothing leaves the clipboard alone.
    @Test func cuttingOnlyTheBoundaryKeepsTheClipboardAndExplainsWhy() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.rectangle.id]
        editor.copySelection()
        let earlier = editor.clipboard
        editor.selection = Set(editor.graph.nodes.values.filter(GroupNodes.isBoundary).map(\.id))
        editor.perform(.cut)
        #expect(editor.clipboard == earlier)
        #expect(editor.refusal?.message == "A group's Group Input and Group Output can't be deleted.")
        #expect(editor.graph.nodes.count == 4)
    }

    @Test func cuttingTheBoundaryWithANodeTakesOnlyTheNode() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selectAll()
        editor.perform(.cut)
        #expect(editor.clipboard?.nodes.map(\.id).sorted() == [grouped.rectangle.id, grouped.extrude.id].sorted())
        #expect(editor.graph.nodes.values.allSatisfy(GroupNodes.isBoundary) && editor.graph.nodes.count == 2)
    }

    @Test func deletingOnlyTheBoundaryExplainsWhyNothingHappened() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let boundary = Set(editor.graph.nodes.values.filter(GroupNodes.isBoundary).map(\.id))
        editor.selection = boundary
        editor.perform(.deleteSelection)
        #expect(editor.refusal?.message == "A group's Group Input and Group Output can't be deleted.")
        #expect(editor.graph.nodes.count == 4)
    }

    @Test func aGroupCantBePastedIntoItself() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        editor.enterGroup(grouped.group)
        let before = editor.document.content
        editor.paste()
        #expect(editor.refusal?.message == "A group can't contain itself.")
        #expect(editor.document.content == before)
    }

    @Test func duplicatingAGroupNodeInsideAGroupPlacesAnotherInstance() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.rectangle.id]
        editor.groupSelection()
        let inner = try #require(editor.selection.first)
        editor.perform(.duplicate)
        let copy = try #require(editor.selection.first)
        #expect(copy != inner && editor.document.definitions.count == 2)
        #expect(editor.graph.nodes[copy]?.inputValues[NodeSetting.group] == editor.graph.nodes[inner]?.inputValues[NodeSetting.group])
    }
}

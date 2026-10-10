import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The inspector for a group node and for Group Input and Group Output (groups spec §6).
@MainActor
struct EditorGroupInspectorTests {
    @Test func aGroupNodeShowsItsDefinitionAndHowManyTimesItIsUsed() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        let panel = try #require(editor.inspectorPage.group)
        #expect(panel.name == "Group" && panel.accent == .purple && panel.definition == grouped.definition.id)
        #expect(panel.side == nil && panel.sockets.isEmpty)
        #expect(panel.usesText == "Used 1 time")
        editor.perform(.duplicate)
        #expect(try #require(editor.groupPanel).usesText == "Used 2 times")
        editor.selection = [grouped.number.id]
        #expect(editor.inspectorPage.group == nil, "a plain node has no group part")
        editor.selection = [grouped.group, grouped.number.id]
        #expect(editor.groupPanel == nil, "nor does a selection of several")
    }

    @Test func groupInputAndOutputListTheSocketsOfTheirSide() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let input = try #require(grouped.definition.inputNode), output = try #require(grouped.definition.outputNode)
        editor.selection = [input.id]
        let inputs = try #require(editor.groupPanel)
        #expect(inputs.side == .input && inputs.sockets.map(\.name) == ["width"] && inputs.sockets.first?.type == .number)
        #expect(inputs.sockets.first?.canMoveUp == false && inputs.sockets.first?.canMoveDown == false)
        editor.selection = [output.id]
        let outputs = try #require(editor.groupPanel)
        #expect(outputs.side == .output && outputs.sockets.map(\.name) == ["solid"])
    }

    @Test func usesCountGroupNodesOnEveryLevel() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.rectangle.id]
        editor.groupSelection()
        #expect(try #require(editor.groupPanel).uses == 1)
        editor.perform(.duplicate)
        #expect(try #require(editor.groupPanel).uses == 2, "two instances of the inner group, both inside the outer one")
        editor.exitGroup()
        editor.selection = [grouped.group]
        #expect(try #require(editor.groupPanel).uses == 1, "the outer group is placed once, on the top level")
    }

    @Test func renamingTheDefinitionRenamesItsGroupNodesAndRefusesAnEmptyOrTakenName() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let id = grouped.definition.id
        editor.renameGroup(id, to: "  Rib ")
        #expect(editor.document.definitions[id]?.name == "Rib")
        #expect(editor.shape(of: try #require(editor.graph.nodes[grouped.group])).title == "Rib")
        editor.renameGroup(id, to: "   ")
        #expect(editor.refusal?.message == "A group needs a name.")
        editor.selection = [grouped.group]
        editor.perform(.duplicate)
        editor.press(.makeUnique, on: try #require(editor.selection.first))
        let other = try #require(editor.document.definitions.values.first { $0.id != id })
        editor.renameGroup(other.id, to: "Rib")
        #expect(editor.refusal?.message == "A group named “Rib” already exists.")
        editor.renameGroup(id, to: "Rib")
        #expect(editor.document.definitions[id]?.name == "Rib", "the same name again does nothing")
    }

    @Test func theAccentChangesAsOneUndoStep() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.setGroupAccent(grouped.definition.id, to: .orange)
        #expect(grouped.current?.accent == .orange)
        editor.setGroupAccent(grouped.definition.id, to: .orange)
        editor.perform(.undo)
        #expect(grouped.current?.accent == .purple, "the repeat recorded nothing")
    }

    @Test func renamingASocketMovesItsWiresInsideAndOnTheGroupNode() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.renameGroupSocket(grouped.definition.id, side: .input, from: "width", to: "w")
        #expect(grouped.current?.inputs.map(\.name) == ["w"])
        #expect(editor.graph.links.contains(Link(from: Endpoint(node: grouped.number.id, socket: "value"),
                                                 to: Endpoint(node: grouped.group, socket: "w"))))
        let input = try #require(grouped.definition.inputNode)
        #expect(grouped.current?.graph.links.contains(wire(input, "w", grouped.rectangle, "width")) == true)
        editor.perform(.undo)
        #expect(grouped.current?.inputs.map(\.name) == ["width"], "one undo step")
        editor.renameGroupSocket(grouped.definition.id, side: .input, from: "width", to: "+")
        #expect(editor.refusal?.message == "“+” is reserved. Choose another name.")
    }

    @Test func socketsMoveUpAndDownTheList() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.transform = CanvasTransform()
        let output = try #require(grouped.definition.outputNode)
        editor.drag(editor.screenPoint(of: grouped.rectangle.id, "profile", input: false),
                    editor.screenPoint(of: output.id, "+", input: true))
        editor.selection = [output.id]
        #expect(editor.groupPanel?.sockets.map(\.name) == ["solid", "profile"])
        #expect(editor.groupPanel?.sockets.map(\.canMoveUp) == [false, true])
        editor.moveGroupSocket(grouped.definition.id, side: .output, named: "profile", by: -1)
        #expect(editor.groupPanel?.sockets.map(\.name) == ["profile", "solid"])
        editor.moveGroupSocket(grouped.definition.id, side: .output, named: "profile", by: -1)
        #expect(editor.groupPanel?.sockets.map(\.name) == ["profile", "solid"], "already first: nothing moves")
        editor.perform(.undo)
        #expect(editor.groupPanel?.sockets.map(\.name) == ["solid", "profile"])
    }

    @Test func aWiredSocketCantBeRemovedAndTheRefusalNamesTheInstance() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let before = editor.document.content
        editor.selection = [grouped.group]
        editor.removeGroupSocket(grouped.definition.id, side: .output, named: "solid")
        #expect(editor.refusal?.message == "“solid” is wired on “Group”. Unwire it first.")
        editor.removeGroupSocket(grouped.definition.id, side: .input, named: "width")
        #expect(editor.refusal?.message == "“width” is wired on “Group”. Unwire it first.")
        #expect(editor.document.content == before)
    }

    @Test func anUnwiredSocketIsRemovedWithItsWiresInsideInOneStep() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.transform = CanvasTransform()
        let output = try #require(grouped.definition.outputNode)
        editor.drag(editor.screenPoint(of: grouped.rectangle.id, "profile", input: false),
                    editor.screenPoint(of: output.id, "+", input: true))
        let withProfile = editor.document.content
        editor.removeGroupSocket(grouped.definition.id, side: .output, named: "profile")
        #expect(grouped.current == grouped.definition)
        editor.perform(.undo)
        #expect(editor.document.content == withProfile)
    }

    @Test func anUnusedDefinitionCanBeDeletedAndAUsedOneCant() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.deleteGroup(grouped.definition.id)
        #expect(editor.refusal?.message == "“Group” is still in use. Delete its group nodes first.")
        editor.selection = [grouped.group]
        editor.deleteSelection()
        editor.deleteGroup(grouped.definition.id)
        #expect(editor.document.definitions.isEmpty)
        editor.perform(.undo)
        #expect(editor.document.definitions.count == 1, "the delete is one undo step")
    }

    @Test func aTypedNameIsCommittedWhenTheSelectionChanges() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let id = grouped.definition.id
        editor.selection = [grouped.group]
        editor.notePendingEntry(PendingEntry(text: "Rib") { editor.renameGroup(id, to: $0) })
        editor.selection = [grouped.number.id]
        #expect(grouped.current?.name == "Rib", "clicking away didn't drop it")
    }

    /// A name typed in the inspector is committed when the selection moves on, and a refusal then belongs to the node
    /// the field was typed for, not to the node just selected.
    @Test func aRefusedNameCommittedByClickingAwayShakesTheNodeItWasTypedFor() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.perform(.duplicate)
        editor.press(.makeUnique, on: try #require(editor.selection.first))
        let other = try #require(editor.document.definitions.values.first { $0.id != grouped.definition.id })
        editor.renameGroup(other.id, to: "Rib")
        editor.selection = [grouped.group]
        let panel = try #require(editor.groupPanel)
        #expect(panel.node == grouped.group)
        // What the Name field records on each keystroke (`GroupPanelView`).
        editor.notePendingEntry(PendingEntry(text: "Rib") { editor.renameGroup(panel.definition, to: $0, on: panel.node) })
        editor.selection = [grouped.number.id]
        #expect(editor.refusal?.message == "A group named “Rib” already exists.")
        #expect(editor.refusal?.node == grouped.group)
        #expect(editor.shakeCount(of: grouped.group) == 1)
        #expect(editor.shakeCount(of: grouped.number.id) == 0, "the node just selected didn't refuse anything")
    }

    /// The node a name was typed for can be gone when the entry is committed (Undo took the Group back): the caption says
    /// so and nothing crashes.
    @Test func aNameCommittedAfterItsGroupWasUndoneOnlySaysSo() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        let panel = try #require(editor.groupPanel)
        editor.notePendingEntry(PendingEntry(text: "Rib") { editor.renameGroup(panel.definition, to: $0, on: panel.node) })
        editor.document.undo()
        #expect(editor.document.definitions.isEmpty)
        editor.commitPendingEntry()
        #expect(editor.refusal?.message == "That group no longer exists.")
        #expect(editor.document.definitions.isEmpty)
    }

    @Test func aRefusedSocketNameShakesTheGroupInputItWasTypedFor() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let input = try #require(grouped.definition.inputNode)
        editor.selection = [input.id]
        let panel = try #require(editor.groupPanel)
        editor.notePendingEntry(PendingEntry(text: "  ") {
            editor.renameGroupSocket(panel.definition, side: .input, from: "width", to: $0, on: panel.node)
        })
        editor.selection = [grouped.rectangle.id]
        #expect(editor.refusal?.message == "A socket needs a name.")
        #expect(editor.shakeCount(of: input.id) == 1)
        #expect(editor.shakeCount(of: grouped.rectangle.id) == 0)
        #expect(grouped.current?.inputs.map(\.name) == ["width"])
    }

    @Test func movingTheFirstSocketUpOrTheLastDownIsIgnored() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [try #require(grouped.definition.inputNode).id]
        let undoName = editor.document.undoName
        editor.moveGroupSocket(grouped.definition.id, side: .input, named: "width", by: -1)
        editor.moveGroupSocket(grouped.definition.id, side: .input, named: "width", by: 1)
        #expect(editor.refusal == nil, "an arrow with nowhere to go says nothing")
        #expect(editor.document.undoName == undoName, "and records nothing")
        #expect(grouped.current?.inputs.map(\.name) == ["width"])
    }

    @Test func theInspectorDrawsTheGroupPartAndTheSocketList() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.number.id]
        let plain = renderHeadless { InspectorPanel(model: editor) }.glyphs.count
        editor.selection = [grouped.group]
        #expect(renderHeadless { InspectorPanel(model: editor) }.glyphs.count > plain)
        editor.enterGroup(grouped.group)
        editor.selection = [try #require(grouped.definition.outputNode).id]
        #expect(renderHeadless { InspectorPanel(model: editor) }.glyphs.count > plain, "the group part and the socket list")
    }
}

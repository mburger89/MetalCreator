import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// ⌘G groups the selection and ⇧⌘G ungroups a group node (groups spec §5), on the top level until C2.
@MainActor
struct GroupKeyTests {
    func key(_ characters: String, _ modifiers: Modifiers) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
    }

    let number = testNode(NumberTestNode.self, id: 1, at: Vector2(0, 0), registry: editorTestRegistry)
    let rectangle = testNode(RectangleTestNode.self, id: 2, at: Vector2(200, 0), registry: editorTestRegistry)
    let extrude = testNode(ExtrudeTestNode.self, id: 3, at: Vector2(400, 0), registry: editorTestRegistry)
    let output = testNode(OutputTestNode.self, id: 4, at: Vector2(600, 0), registry: editorTestRegistry)

    func editor() -> EditorModel {
        makeEditor([number, rectangle, extrude, output], [
            wire(number, "value", rectangle, "width"), wire(rectangle, "profile", extrude, "profile"),
            wire(extrude, "solid", output, "solid"),
        ])
    }

    @Test func commandGGroupsAndShiftCommandGUngroups() {
        #expect(GraphKeyBindings.command(for: key("g", .command), paletteOpen: false) == .group)
        #expect(GraphKeyBindings.command(for: key("G", [.command, .shift]), paletteOpen: false) == .ungroup)
        #expect(GraphKeyBindings.command(for: key("g", .command), paletteOpen: true) == nil)
    }

    @Test func groupingSelectsTheGroupNodeAndUngroupingSelectsWhatCameBack() throws {
        let editor = editor()
        editor.selection = [rectangle.id, extrude.id]
        #expect(editor.perform(.group))
        let node = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(editor.selection.count == 1 && node.typeID == GroupNodes.groupTypeID)
        #expect(editor.graph.nodes.count == 3)
        #expect(editor.shape(of: node).inputs.map(\.name) == ["width"])
        #expect(editor.shape(of: node).outputs.map(\.name) == ["solid"])

        #expect(editor.perform(.ungroup))
        #expect(editor.selection.count == 2)
        #expect(editor.graph.nodes.count == 4)
        #expect(editor.document.definitions.isEmpty)
        editor.perform(.undo)
        editor.perform(.undo)
        #expect(Set(editor.graph.nodes.keys) == [number.id, rectangle.id, extrude.id, output.id])
    }

    @Test func duplicatingAGroupNodePlacesAnotherInstance() throws {
        let editor = editor()
        editor.selection = [rectangle.id, extrude.id]
        editor.groupSelection()
        let first = try #require(editor.selection.first)
        editor.perform(.duplicate)
        let second = try #require(editor.selection.first)
        #expect(second != first)
        #expect(editor.document.definitions.count == 1)
        #expect(editor.graph.nodes[second]?.inputValues[NodeSetting.group] == editor.graph.nodes[first]?.inputValues[NodeSetting.group])
        #expect(editor.shape(of: try #require(editor.graph.nodes[second])).outputs.map(\.name) == ["solid"])
    }

    @Test func refusedGroupingShowsWhy() {
        let editor = editor()
        #expect(!editor.perform(.group), "nothing selected: the key goes on")
        editor.selection = [extrude.id, output.id]
        editor.groupSelection()
        #expect(editor.refusal?.message == "An Output node can't go in a group.")
        #expect(editor.document.definitions.isEmpty)
        editor.selection = [number.id]
        editor.ungroupSelection()
        #expect(editor.refusal?.message == "Select one group node to ungroup.")
    }
}

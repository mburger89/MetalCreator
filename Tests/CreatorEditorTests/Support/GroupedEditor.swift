// Test fixture file: an editor over a document whose Rectangle and Extrude are already grouped.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Number → Rectangle (`width`) → Extrude → Output, with Rectangle and Extrude grouped (⌘G): the top level then holds
/// Number, the group node (`group`, input `width`, output `solid`) and Output.
@MainActor
struct GroupedEditor {
    let editor: EditorModel
    let number = testNode(NumberTestNode.self, id: 1, at: Vector2(0, 0), registry: editorTestRegistry)
    let rectangle = testNode(RectangleTestNode.self, id: 2, at: Vector2(200, 0), registry: editorTestRegistry)
    let extrude = testNode(ExtrudeTestNode.self, id: 3, at: Vector2(400, 0), registry: editorTestRegistry)
    let output = testNode(OutputTestNode.self, id: 4, at: Vector2(600, 0), registry: editorTestRegistry)
    let group: NodeID
    let definition: GroupDefinition

    init(parameters: [GraphParameter] = []) throws {
        let all = [number, rectangle, extrude, output]
        editor = makeEditor(all, [
            wire(number, "value", rectangle, "width"), wire(rectangle, "profile", extrude, "profile"),
            wire(extrude, "solid", output, "solid"),
        ], parameters: parameters)
        editor.selection = [rectangle.id, extrude.id]
        editor.groupSelection()
        group = try #require(editor.selection.first)
        definition = try #require(editor.document.definitions.values.first)
    }

    /// The definition as it is now.
    var current: GroupDefinition? { editor.document.definitions[definition.id] }
}

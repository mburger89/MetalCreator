import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Headless frames of the inspector for nothing selected and for each kind of node, including a
/// missing one: every row kind builds with MetalUI's controls without trapping.
@MainActor
struct InspectorRenderTests {
    @Test(arguments: [nil, 1, 2, 3, 4, 5])
    func theInspectorDraws(_ selected: Int?) {
        let editor = sampleEditor(dock: .left)
        editor.selection = selected.map { [nodeID($0)] } ?? []
        #expect(!renderHeadless { InspectorPanel(model: editor) }.glyphs.isEmpty)
    }

    /// M3's `.vector` and `.parameterPicker` rows, the picker with and without parameters, and an
    /// unset optional input.
    @Test func vectorParameterAndOptionalRowsDraw() {
        let transform = testNode(TransformTestNode.self, id: 5, at: .zero)
        let picker = testNode(GraphParameterTestNode.self, id: 6, at: Vector2(0, 200))
        let grid = testNode(GridPointsTestNode.self, id: 7, at: Vector2(0, 400))
        let width = GraphParameter(name: "Width", type: .number, value: .number(60))
        let editor = makeEditor([transform, picker, grid], parameters: [width], registry: inspectorTestRegistry)
        for id in [transform.id, picker.id, grid.id] {
            editor.selection = [id]
            #expect(!renderHeadless { InspectorPanel(model: editor) }.glyphs.isEmpty)
        }
        let empty = makeEditor([picker], registry: inspectorTestRegistry)
        empty.selection = [picker.id]
        #expect(!renderHeadless { InspectorPanel(model: empty) }.glyphs.isEmpty)
    }
}

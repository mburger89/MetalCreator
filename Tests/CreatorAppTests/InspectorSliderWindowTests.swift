import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// A drag on the inspector's slider, through the app's real window (gap M5-a, used again by the C10 adoption): MetalUI's
/// `Slider(onEditingChanged:)` pairs the press and the release, so each drag is exactly one undo step.
@MainActor
struct InspectorSliderWindowTests {
    /// The window showing a Rectangle node, selected, and its inspector's first slider (Width).
    func selectedRectangle() async throws -> (app: AppWindow, node: Node, slider: TestElement) {
        var builder = GraphBuilder()
        let node = builder.add(RectangleNode.self, at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        #expect(app.editor.selection == [node.id])
        let slider = try #require(app.window.elements(role: .slider).first)
        return (app, node, slider)
    }

    /// A drag along the slider's track from `from` to `to`, each a fraction of its width.
    func drag(_ app: AppWindow, _ slider: TestElement, from: Float, to: Float) {
        let y = slider.frame.origin.y + slider.frame.size.height / 2
        let width = slider.frame.size.width.value
        app.window.drag(from: Point(x: slider.frame.origin.x + Pixels(width * from), y: y),
                        to: Point(x: slider.frame.origin.x + Pixels(width * to), y: y), steps: 6)
    }

    @Test func aDragIsOneUndoStep() async throws {
        let (app, node, slider) = try await selectedRectangle()
        drag(app, slider, from: 0.1, to: 0.9)
        guard case .number(let width)? = app.editor.graph.nodes[node.id]?.inputValues["width"] else {
            Issue.record("the drag wrote no width")
            return
        }
        #expect(width > 0)
        #expect(app.editor.document.undoName == "Change Width")
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil, "one undo undoes the whole drag")
        #expect(!app.editor.document.canUndo)
    }

    @Test func twoDragsAreTwoUndoSteps() async throws {
        let (app, node, slider) = try await selectedRectangle()
        drag(app, slider, from: 0.1, to: 0.9)
        let first = app.editor.graph.nodes[node.id]?.inputValues["width"]
        drag(app, slider, from: 0.9, to: 0.4)
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] != first)
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == first, "the second drag was a step of its own")
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil && !app.editor.document.canUndo)
    }
}

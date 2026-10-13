import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// An input method composing in an inspector number field, through the app's real window (MetalUI C28, gap CT-d): the
/// marked text is the field's own, the model hears of the committed text only, and a press elsewhere while composing
/// drops the composition (MetalUI `IM-I`) and leaves no pending value. The press test types nothing before composing;
/// text committed before a composition is pinned by the canvas note and title tests.
@MainActor
struct InspectorFieldCompositionWindowTests {
    /// The window showing a Rectangle node, selected, and its Width field clicked, all of it selected.
    func widthField() async throws -> (app: AppWindow, node: Node) {
        var builder = GraphBuilder()
        let node = builder.add(RectangleNode.self, at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        #expect(app.editor.selection == [node.id])
        let fields = try app.window.elements { $0.role == .textField && $0.frame.origin.x.value >= Float(app.inspectorColumnStart) }
        let width = try #require(fields.first)
        try app.window.click(width)
        app.window.typeKey("a", modifierFlags: .primary)
        return (app, node)
    }

    @Test func markedTextIsNotAPendingValueAndACommittedCandidateIs() async throws {
        let (app, node) = try await widthField()
        #expect(app.window.setMarkedText("3"))
        #expect(app.editor.pendingEntry == nil, "the field holds the marked text; the model has no pending value")
        #expect(app.window.commitMarkedText("33"))
        #expect(app.editor.pendingEntry?.text == "33")
        app.window.typeKey(.return)
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == .number(33))
        #expect(app.editor.document.undoName == "Change Width")
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil && !app.editor.document.canUndo, "one step")
    }

    @Test func aCancelledCompositionLeavesTheFieldAlone() async throws {
        let (app, node) = try await widthField()
        #expect(app.window.setMarkedText("9"))
        #expect(app.window.cancelMarkedText())
        #expect(app.editor.pendingEntry == nil)
        app.window.typeText("7")
        #expect(app.editor.pendingEntry?.text == "7", "the select-all survived: typing replaced the value")
        app.window.typeKey(.return)
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == .number(7))
    }

    @Test(arguments: InertSpot.allCases)
    func aPressOnChromeWhileComposingCommitsNothingOfIt(spot: InertSpot) async throws {
        let (app, node) = try await widthField()
        #expect(app.window.setMarkedText("9"))
        #expect(app.window.markedText == "9")
        app.window.click(at: try spot.point(in: app))
        try await app.window.runUntilIdle()
        #expect(app.window.markedText == "")
        #expect(try app.window.focusedElement == nil)
        #expect(app.editor.pendingEntry == nil, "no stale pending entry survives the press")
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil)
        #expect(!app.editor.document.canUndo)
    }
}

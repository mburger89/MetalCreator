import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// A number typed into an inspector field commits when a press elsewhere takes the focus (human check M6-6; gap CT-a,
/// adopted from MetalUI C24): the field's focus-loss commit, with the press landing on inert chrome or on another field.
/// The commit runs in the frame after the press, so each test runs `runUntilIdle()`.
@MainActor
struct InspectorFieldResignWindowTests {
    /// The window showing a Rectangle node, selected, and its inspector's number fields (Width, then Height).
    func selectedRectangle() async throws -> (app: AppWindow, node: Node, fields: [TestElement]) {
        var builder = GraphBuilder()
        let node = builder.add(RectangleNode.self, at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        #expect(app.editor.selection == [node.id])
        let fields = try app.window.elements { $0.role == .textField && $0.frame.origin.x.value >= Float(app.inspectorColumnStart) }
        #expect(fields.count >= 2, "Width and Height")
        return (app, node, fields)
    }

    /// Selects a field's text and types `text` over it.
    func type(_ text: String, into field: TestElement, in app: AppWindow) throws {
        try app.window.click(field)
        app.window.typeKey("a", modifierFlags: .primary)
        app.window.typeText(text)
    }

    @Test(arguments: InertSpot.allCases)
    func aPressOnInertChromeCommitsATypedValueInOneStep(spot: InertSpot) async throws {
        let (app, node, fields) = try await selectedRectangle()
        try type("33", into: fields[0], in: app)
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil, "nothing is committed while typing")
        app.window.click(at: try spot.point(in: app))
        try await app.window.runUntilIdle()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == .number(33))
        #expect(app.editor.document.undoName == "Change Width")
        #expect(try app.window.focusedElement == nil)
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil && !app.editor.document.canUndo, "one step")
    }

    /// A viewport press commits the typed value (a model commit, `AppModel+Viewport`) and takes the focus off the field.
    @Test func aPressOnTheViewportCommitsATypedValueAndClearsTheFocus() async throws {
        let (app, node, fields) = try await selectedRectangle()
        try type("33", into: fields[0], in: app)
        app.window.click(at: Point(x: Pixels(700), y: Pixels(300)))
        try await app.window.runUntilIdle()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == .number(33))
        #expect(try app.window.focusedElement == nil)
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil && !app.editor.document.canUndo, "one step")
    }

    /// A to B: the press lands on Height, so Width commits (once) and Height has the focus.
    @Test func aPressIntoAnotherFieldCommitsTheFirstOnceAndMovesTheFocus() async throws {
        let (app, node, fields) = try await selectedRectangle()
        try type("33", into: fields[0], in: app)
        try app.window.click(fields[1])
        try await app.window.runUntilIdle()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == .number(33))
        let focused = try #require(try app.window.focusedElement)
        #expect(focused.role == .textField && focused.frame.origin.y == fields[1].frame.origin.y, "Height has the focus")
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil && !app.editor.document.canUndo, "committed once")
    }

    /// A secondary press resigns nothing: the typed value is still pending, and typing carries on.
    @Test func aSecondaryPressOnInertChromeLeavesATypedValuePending() async throws {
        let (app, node, fields) = try await selectedRectangle()
        try type("33", into: fields[0], in: app)
        app.window.rightClick(at: try InertSpot.panelGlass.point(in: app))
        try await app.window.runUntilIdle()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil)
        #expect(try app.window.focusedElement?.role == .textField)
        #expect(app.editor.pendingEntry?.text == "33")
    }
}

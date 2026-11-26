import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The canvas's gestures reach the model: a click selects the view under it and a drag moves it as one step.
@MainActor
@Suite("Sheet canvas input")
struct SheetCanvasInputTests {
    private func open() async throws -> (EditorHarness, DrawingWindow, DrawingView) {
        let view = EditorDocuments.view(at: Vector2(148, 105))
        let sheet = DrawingSheet(name: "Sheet 1", size: .a4, orientation: .landscape, views: [view])
        let harness = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        let window = try await DrawingWindow.open(scaleFactor: 2) { SheetCanvas(model: harness.model) }
        harness.model.transform = SheetTransform(offset: Vector2(20, 20 + 210 * 3), zoom: 3)
        window.redraw()
        try await window.window.runUntilIdle()
        return (harness, window, view)
    }

    @Test func aClickSelectsTheViewAndADragMovesItAsOneStep() async throws {
        let (h, window, view) = try await open()
        let centre = DrawingWindow.point(h.canvas(148, 105))
        window.window.click(at: centre)
        #expect(h.model.selection == [view.id])
        #expect(h.log.commits.isEmpty)
        window.window.drag(from: centre, to: Point(x: centre.x + 30, y: centre.y))
        #expect(h.log.commits.allSatisfy { $0.name == "Move View" } && !h.log.commits.isEmpty)
        #expect(Set(h.log.commits.map(\.coalescingKey)).count == 1, "one coalescing key, so one undo step")
        let moved = try #require(h.model.document.sheets[0].view(view.id)?.center)
        #expect(abs(moved.x - 158) < 0.5, "30 points at 3 points a millimetre")
    }

    @Test func aScrollPans() async throws {
        let (h, window, _) = try await open()
        let before = h.model.transform
        window.window.scroll(at: Point(x: Pixels(300), y: Pixels(300)), byDeltaX: 5, deltaY: 7)
        #expect(h.model.transform.zoom == before.zoom)
        #expect(h.model.transform.offset != before.offset)
    }

    @Test func theLettersAGAndRChooseSymbolTools() {
        for (key, tool) in [
            (KeyEquivalent("a"), DrawingTool.datum), (KeyEquivalent("g"), .featureControlFrame),
            (KeyEquivalent("r"), .surfaceFinish),
        ] {
            #expect(SheetCanvasInput.key(key, modifiers: []) == .tool(tool))
            #expect(SheetCanvasInput.key(KeyEquivalent(Character(key.character.uppercased())), modifiers: []) == .tool(tool))
        }
        #expect(SheetCanvasInput.key("a", modifiers: .primary) == nil, "a chord belongs to the menus")
    }
}

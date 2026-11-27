import CreatorGeometry
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// What a drag step costs: the work counted, never timed (speed plan R7).
@MainActor
@Suite("Drag work")
struct DragWorkTests {
    @Test func draggingADimensionMapsNoViewAfterThePress() throws {
        let s = SelectionScene.make([.horizontal])
        let model = s.h.model
        let start = s.centre(of: SelectionScene.horizontal) - Vector2(7, 0)
        model.primaryChanged(to: s.h.canvas(start.x, start.y), modifiers: [])
        let afterPress = model.lineworkMapped
        #expect(afterPress >= 1, "the first compose mapped the view")
        for step in 1...10 {
            let point = start + Vector2(0, -Double(step) * 0.5)
            model.primaryChanged(to: s.h.canvas(point.x, point.y), modifiers: [])
        }
        #expect(model.lineworkMapped == afterPress, "ten drag steps recomposed the sheet without mapping a view")
        let moved = try #require(s.dimension(SelectionScene.horizontal))
        #expect(abs(moved.placement.offset - 5) < 1e-9, "the drag moved the dimension")
        model.primaryEnded(at: s.h.canvas(start.x, start.y - 5), modifiers: [])
    }
}

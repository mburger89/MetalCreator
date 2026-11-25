import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The toolbar is a `ViewThatFits` over rows that move tools into a "More" menu from the end, so no label is cut short.
@MainActor
@Suite("Drawing toolbar")
struct DrawingToolbarTests {
    private func labels(width: Float, model: DrawingEditorModel) async throws -> [String] {
        let window = try await DrawingWindow.open(size: Size(width: Pixels(width), height: Pixels(100)), scaleFactor: 2) {
            DrawingToolbar(model: model)
        }
        return try window.window.elements(where: { $0.role == .button || $0.role == .menuButton }).compactMap(\.label)
    }

    private func model() -> DrawingEditorModel {
        EditorHarness(document: EditorDocuments.document([DrawingSheet(name: "Sheet 1")]), sheet: nil).model
    }

    @Test func theRowsMoveToolsIntoMoreFromTheEnd() async throws {
        let model = model()
        let wide = try await labels(width: 1000, model: model)
        #expect(wide == ["Base View", "Projected View"])
        let middle = try await labels(width: 200, model: model)
        #expect(middle == ["Base View", "More"], "the last tool moved first: \(middle)")
        let narrow = try await labels(width: 100, model: model)
        #expect(narrow == ["More"], "\(narrow)")
    }

    @Test func theChosenToolIsMarked() async throws {
        let model = model()
        model.press(.projectedView)
        let wide = try await labels(width: 1000, model: model)
        #expect(wide == ["Base View", "Projected View ✓"])
        let middle = try await labels(width: 200, model: model)
        #expect(middle == ["Base View", "More ✓"])
    }
}

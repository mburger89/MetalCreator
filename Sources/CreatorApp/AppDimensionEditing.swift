import CreatorSketchEditor
import CreatorViewport

/// The one `DimensionEditing` the viewport talks to: it routes a dimension's ID to whoever owns it. A "sketch/…" ID goes to the open
/// sketch's editor; any other has no owner yet (model dimensions join in DIM-3), so no box opens and a commit is refused.
@MainActor
final class AppDimensionEditing: DimensionEditing {
    weak var app: AppModel?

    private var sketchEditor: SketchEditorModel? { app?.sketch?.editor }

    private func isSketch(_ id: OverlayDimensionID) -> Bool { id.rawValue.hasPrefix("sketch/") }

    func valueBoxContent(for id: OverlayDimensionID) -> DimensionValueBoxContent? {
        guard isSketch(id) else { return nil }
        return sketchEditor?.valueBoxContent(for: id)
    }

    func commitValue(_ text: String, to id: OverlayDimensionID) async -> DimensionCommitOutcome {
        guard isSketch(id), let editor = sketchEditor else { return .refused("That dimension is gone.") }
        return await editor.commitValue(text, to: id)
    }

    func valueBoxClosed(_ id: OverlayDimensionID, by ending: DimensionValueBoxEnding) {
        guard isSketch(id) else { return }
        sketchEditor?.valueBoxClosed(id, by: ending)
    }
}

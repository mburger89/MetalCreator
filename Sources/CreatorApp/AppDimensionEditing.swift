import CreatorSketchEditor
import CreatorViewport

/// The one `DimensionEditing` the viewport talks to: it routes a dimension's ID to whoever owns it. A "sketch/…" ID goes to the open
/// sketch's editor, a "feature/…" ID to the app's feature editing (`FeatureDimensionEditing`); any other has no owner, so no box
/// opens and a commit is refused.
@MainActor
final class AppDimensionEditing: DimensionEditing {
    weak var app: AppModel?

    private var sketchEditor: SketchEditorModel? { app?.sketch?.editor }

    private func isSketch(_ id: OverlayDimensionID) -> Bool { id.rawValue.hasPrefix("sketch/") }

    private func isFeature(_ id: OverlayDimensionID) -> Bool { id.rawValue.hasPrefix("feature/") }

    func valueBoxContent(for id: OverlayDimensionID) -> DimensionValueBoxContent? {
        if isFeature(id) {
            guard let app, let dimension = app.featureDimensions[id] else { return nil }
            return FeatureDimensionEditing.boxContent(dimension, units: app.units)
        }
        guard isSketch(id) else { return nil }
        return sketchEditor?.valueBoxContent(for: id)
    }

    func commitValue(_ text: String, to id: OverlayDimensionID) async -> DimensionCommitOutcome {
        if isFeature(id) {
            guard let app else { return .refused("That dimension is gone.") }
            return await app.commitFeatureValue(text, to: id)
        }
        guard isSketch(id), let editor = sketchEditor else { return .refused("That dimension is gone.") }
        // The sketch's value commit is a checked step like a feature's (spec §7): results are held while the editor commits and the
        // host checks (`events.checkValueCommit`), and released on every outcome, a refusal by the editor itself included.
        guard let document = app?.document else { return .refused("That dimension is gone.") }
        document.holdResults()
        defer { document.releaseResults() }
        return await editor.commitValue(text, to: id)
    }
}

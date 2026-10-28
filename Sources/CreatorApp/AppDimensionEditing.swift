import CreatorGraph
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

    /// Pin or Unpin for a feature dimension; a sketch's own dimensions have none (pins are feature dimensions).
    func menuActions(for id: OverlayDimensionID) -> [HostMenuAction] {
        guard let pin = pin(for: id) else { return [] }
        let action = pin.isPinned ? HostMenuAction(title: "Unpin Dimension", key: "unpin")
                                  : HostMenuAction(title: "Pin Dimension", key: "pin")
        return [action]
    }

    func performMenuAction(_ action: HostMenuAction, for id: OverlayDimensionID) {
        guard let app, let pin = pin(for: id) else { return }
        switch action.key {
        case "pin" where !pin.isPinned:
            edit(.pinDimension(pin.pin), name: UndoName.pinDimension, on: app)
        case "unpin" where pin.isPinned:
            edit(.unpinDimension(pin.pin), name: UndoName.unpinDimension, on: app)
        default:
            break
        }
    }

    /// Pins or unpins through the editor. The pin's node can be gone by now; that refusal is not shown (the menu closes and the
    /// dimension with it), but any other failure is a bug and stops a debug build.
    private func edit(_ command: GraphCommand, name: String, on app: AppModel) {
        do {
            try app.editor.edit(command, name: name)
        } catch {
            if case .nodeNotFound = error { return }
            assertionFailure("Pin edit failed: \(error)")
        }
    }

    /// A reference's source ("from Number “width”").
    func hoverNote(for id: OverlayDimensionID) -> String? {
        guard isFeature(id), case .reference(let source)? = app?.featureDimensions[id]?.editing else { return nil }
        return source
    }

    private func pin(for id: OverlayDimensionID) -> (pin: DimensionPin, isPinned: Bool)? {
        guard isFeature(id), let dimension = app?.featureDimensions[id] else { return nil }
        return (DimensionPin(node: dimension.node, target: dimension.spec.target), dimension.isPinned)
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
        app?.sketchCheckBaseline = document.performCount
        app?.sketchCheckDocument = document
        defer {
            app?.sketchCheckBaseline = nil
            app?.sketchCheckDocument = nil
            document.releaseResults()
        }
        return await editor.commitValue(text, to: id)
    }
}

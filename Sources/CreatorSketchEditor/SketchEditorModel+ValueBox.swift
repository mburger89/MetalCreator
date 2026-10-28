import CreatorGeometry
import CreatorSketch
import CreatorViewport

/// The sketch's dimensions answer the viewport's value box (spec §4.5, §7), and so does the Dimension tool's pending one
/// (`SketchEditorModel+PendingDimension`).
extension SketchEditorModel: DimensionEditing {
    /// A driving, unwired dimension opens with its exact value in the document's unit; any other, or an ID that names no sketch
    /// dimension, opens no box.
    public func valueBoxContent(for id: OverlayDimensionID) -> DimensionValueBoxContent? {
        if id == SketchDimensionDrawing.pendingID {
            guard let pending, pending.isDriving, pending.phase != .picked else { return nil }
            return DimensionValueBoxContent(text: units.editText(pending.value, quantity: pending.kind.quantity))
        }
        guard let dimensionID = SketchDimensionDrawing.dimensionID(from: id), let dimension = sketch.dimensions[dimensionID],
              dimension.isDriving, !wiredDimensions.contains(dimensionID) else { return nil }
        return DimensionValueBoxContent(text: units.editText(dimension.value, quantity: dimension.kind.quantity))
    }

    /// Takes the text typed into the box. The inspector's checks refuse with their own sentences; an unchanged value is
    /// accepted with no step; the edited sketch must solve (nothing is committed otherwise); then one "Change Dimension" step
    /// is committed and the host checks what it did.
    public func commitValue(_ text: String, to id: OverlayDimensionID) async -> DimensionCommitOutcome {
        if id == SketchDimensionDrawing.pendingID { return commitPendingValue(text) }
        guard let dimensionID = SketchDimensionDrawing.dimensionID(from: id),
              let check = checkedEdit(text, of: dimensionID) else {
            return .refused("That dimension is gone.")
        }
        switch check {
        case .refused(let message):
            return .refused(message)
        case .unchanged:
            return .accepted
        case .change(let edited, let description):
            switch SketchSolver.solve(edited).status {
            case .overConstrained: return .refused("That value would over-constrain the sketch.")
            case .failed(let reason): return .refused(reason)
            case .solved, .underConstrained: break
            }
            commit(edited, description, named: SketchStepName.changeDimension)
            if let message = await events.checkValueCommit() { return .refused(message) }
            return .accepted
        }
    }
}

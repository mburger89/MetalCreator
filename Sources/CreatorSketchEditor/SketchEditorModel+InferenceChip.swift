import CreatorViewport

extension SketchEditorModel {
    /// The glyphs of what the next click would infer, placed by the pointer on screen clear of the readout's chip
    /// (`InferenceChip`), or `nil` with nothing inferred or no pointer over the view.
    public var inferenceChip: InferenceChip? {
        guard let pointer = pointerOnScreen, !viewSize.isEmpty else { return nil }
        return InferenceChip(kinds: preview.inferred, pointer: pointer, in: viewSize, modelArea: modelArea,
                             avoiding: readoutChip)
    }
}

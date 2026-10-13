import CreatorViewport
import MetalUI

/// The pointer readout's chip (`SketchEditorModel.readoutChip`), when there is one. The host draws it over the
/// viewport and its chrome, whose points are the window's; it never takes the pointer. This is glue: the text and
/// the placement are the model's.
public struct PointerReadoutView: Component {
    let model: SketchEditorModel
    /// MetalUI's text measurer (C23): the chips are as wide as their text (gap S5-c).
    @Environment(\.textMeasurer) var measurer

    public init(model: SketchEditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let measure = TextMeasure(measurer)
        return ZStack(alignment: .topLeading) {
            if let chip = model.readoutChip(measuring: measure) { ReadoutChipView(chip: chip) }
            if let chip = model.inferenceChip(measuring: measure) { InferenceChipView(chip: chip) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

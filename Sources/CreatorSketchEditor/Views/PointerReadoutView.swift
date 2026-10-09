import MetalUI

/// The pointer readout's chip (`SketchEditorModel.readoutChip`), when there is one. The host draws it over the
/// viewport and its chrome, whose points are the window's; it never takes the pointer. This is glue: the text and
/// the placement are the model's.
public struct PointerReadoutView: Component {
    let model: SketchEditorModel

    public init(model: SketchEditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            if let chip = model.readoutChip { ReadoutChipView(chip: chip) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

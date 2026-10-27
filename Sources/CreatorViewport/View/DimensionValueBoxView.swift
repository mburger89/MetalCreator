import MetalUI

/// The value box of a dimension being edited (spec §7), drawn where `ViewportModel.placedValueBox(measuring:)` puts it: a text
/// field over the dimension's text, the editor's note above it, and "Checking…" or the refusal's message in red below it. It takes
/// focus as it appears (`DimensionValueBoxField`), in the host's `fieldKeyContext` when it names one.
struct DimensionValueBoxView: Component {
    let model: ViewportModel
    let placed: PlacedValueBox

    var content: some ElementGroup {
        let box = placed.box
        let originX = Pixels(Float(placed.origin.x))
        let originY = Pixels(Float(placed.origin.y))
        let height = Pixels(Float(placed.size.height))
        ZStack(alignment: .topLeading) {
            if let note = box.note {
                ProposalText(note)
                    .font(.caption)
                    .foregroundStyle(model.hintColor)
                    .frame(height: height, alignment: .leading)
                    .offset(x: originX, y: originY - height)
            }
            if box.isChecking {
                ProposalText("Checking…")
                    .font(.caption)
                    .foregroundStyle(model.hintColor)
                    .frame(height: height, alignment: .leading)
                    .offset(x: originX, y: originY + height)
            } else if let message = box.message {
                ProposalText(message)
                    .font(.caption)
                    .foregroundStyle(model.textColor(for: .conflicting))
                    .frame(height: height, alignment: .leading)
                    .offset(x: originX, y: originY + height)
            }
            if model.fieldKeyContext.isEmpty {
                DimensionValueBoxField(model: model, box: box)
                    .frame(width: Pixels(Float(placed.size.width)), height: height)
                    .offset(x: originX, y: originY)
            } else {
                DimensionValueBoxField(model: model, box: box)
                    .frame(width: Pixels(Float(placed.size.width)), height: height)
                    .offset(x: originX, y: originY)
                    .keyContext(model.fieldKeyContext)
            }
        }
    }
}

import MetalUI

/// A dimension's hover note (`ViewportModel.dimensionHoverNote`): small text in `ink` on a rounded `fill`, its top-left corner at
/// `origin`, `size` big (the text's measure plus `padding` at each side: a text given room centres in it). It takes no pointer.
struct DimensionHoverChip: Component {
    /// Room between the text and the chip's edge at each side.
    static let padding = 4.0

    let note: String
    let origin: ScreenPoint
    let size: ViewportSize
    let ink: Color
    let fill: Color

    var content: some ElementGroup {
        // A top-leading stack as big as the room it is given: a smaller one would be centred in it, and `origin` is a corner.
        ZStack(alignment: .topLeading) {
            ProposalText(note)
                .font(.caption)
                .foregroundStyle(ink)
                .frame(width: Pixels(Float(size.width)), height: Pixels(Float(size.height)))
                .background(fill, in: RoundedRectangle(cornerRadius: Pixels(4)))
                .offset(x: Pixels(Float(origin.x)), y: Pixels(Float(origin.y)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

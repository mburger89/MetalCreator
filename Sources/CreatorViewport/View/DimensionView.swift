import MetalUI

/// One placed dimension (`PlacedDimension`, in view points): its lines and arrows in `ink`, its text on a `fill` box, and
/// the pin mark of a pinned one. A ghosted dimension is drawn faint. Hit testing is left to the model
/// (`ViewportModel.dimension(at:)`), so none of it takes events.
struct DimensionView: Component {
    let placed: PlacedDimension
    let style: DimensionStyle
    let ink: Color
    let fill: Color

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            DimensionLinesShape(segments: placed.segments)
                .stroke(ink, lineWidth: Pixels(Float(style.lineWidth)))
            DimensionArrowsShape(arrows: placed.arrows, length: style.arrowLength, width: style.arrowWidth)
                .fill(ink)
            if placed.showsText {
                ProposalText(placed.text)
                    .font(.caption)
                    .foregroundStyle(ink)
                    .frame(width: Pixels(Float(placed.textSize.width)), height: Pixels(Float(placed.textSize.height)))
                    .background(fill, in: RoundedRectangle(cornerRadius: Pixels(4)))
                    .offset(x: Pixels(Float(placed.textOrigin.x)), y: Pixels(Float(placed.textOrigin.y)))
            }
            if let pin = placed.pinMark {
                Circle()
                    .fill(ink)
                    .frame(width: Pixels(Float(2 * style.pinMarkRadius)), height: Pixels(Float(2 * style.pinMarkRadius)))
                    .offset(x: Pixels(Float(pin.x - style.pinMarkRadius)), y: Pixels(Float(pin.y - style.pinMarkRadius)))
            }
        }
        .opacity(placed.isGhosted ? 0.4 : 1)
        .allowsHitTesting(false)
    }
}

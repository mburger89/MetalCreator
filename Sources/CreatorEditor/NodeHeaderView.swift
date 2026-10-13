import CreatorGraph
import CreatorStyle
import MetalUI

/// A node's header strip: dark text on the category colour, the status badge at the right. Every input is a stored
/// value, so `==` covers all `content` reads.
struct NodeHeaderView: Component, Equatable {
    let title: String
    let accent: HexColor
    let state: NodeState?
    let palette: Palette

    var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(palette.textOnAccent.color)
            Spacer()
            StatusBadgeView(state: state, palette: palette).equatable()
        }
        .padding(Edges(top: Pixels(0), right: Pixels(8), bottom: Pixels(0), left: Pixels(8)))
        .frame(width: NodeLayout.width.px, height: NodeLayout.headerHeight.px)
        .background(accent.color)
    }
}

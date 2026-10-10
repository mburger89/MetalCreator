import CreatorGraph
import CreatorStyle
import MetalUI

/// The status badge: MetalUI's spinner (`ProgressView`, gap M5-j) while the node evaluates, then the time in ms, ⚠
/// or ✕, on a dark capsule so it reads on any header colour. The warning or error message is its tooltip.
struct StatusBadgeView: Component {
    let state: NodeState?
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let text = StatusBadge.text(for: state)
        let colour = state.map(palette.status) ?? palette.secondaryText
        let isBusy = StatusBadge.isBusy(state)
        return HStack(spacing: Pixels(0)) {
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(colour.color)
            }
        }
        .padding(Edges(top: Pixels(1), right: Pixels(5), bottom: Pixels(1), left: Pixels(5)))
        .background(palette.panelBase.color, in: Capsule())
        .opacity(text.isEmpty && !isBusy ? 0 : 1)
        .help(StatusBadge.message(for: state) ?? "")
    }
}

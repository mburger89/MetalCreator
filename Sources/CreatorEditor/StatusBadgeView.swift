import CreatorGraph
import MetalUI

/// The status badge: a spinner glyph, the time in ms, ⚠ or ✕, on a dark capsule so it reads on
/// any header colour. The warning or error message is its tooltip.
struct StatusBadgeView: Component {
    let state: NodeState?

    var content: some ElementGroup {
        let text = StatusBadge.text(for: state)
        let colour = state.map(Palette.status) ?? Palette.secondaryText
        return HStack(spacing: Pixels(0)) {
            Text(text)
                .font(.caption2)
                .foregroundStyle(colour.color)
        }
        .padding(Edges(top: Pixels(1), right: Pixels(5), bottom: Pixels(1), left: Pixels(5)))
        .background(Palette.panelBase.color, in: Capsule())
        .opacity(text.isEmpty ? 0 : 1)
        .help(StatusBadge.message(for: state) ?? "")
    }
}

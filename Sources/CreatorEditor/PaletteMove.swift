import MetalUI

/// Moves the add-node palette's highlight. Bound to ↑/↓ in `GraphPanelInput.keymap`, because
/// the window keymap runs before the focused search field claims the arrows (docs/metalui-gaps.md M5-h).
public struct PaletteMove: Action, Equatable, Sendable {
    public var step: Int

    public init(step: Int) {
        self.step = step
    }
}

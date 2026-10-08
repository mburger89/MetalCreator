import MetalUI

/// **Stopgap for MetalUI C7 item 5** ("modifiers during a drag", docs/metalui-gaps.md gap 5). MetalUI's
/// `DragGesture.Value` carries no modifier keys, so Shift-drag pan and ⌥-drag zoom (spec §9) read the held set
/// from the window's `.modifiersChanged` events instead. When C7 lands (provisionally `DragGesture.Value.modifiers`),
/// `ViewportView` reads the gesture's value and this type is deleted.
@MainActor
public final class ViewportModifierTracker {
    public private(set) var held: ViewportModifiers = []

    public init() {}

    /// Chains onto `window.onInput`, keeping whatever handler was already there, and claims nothing.
    public func install(on window: Window) {
        let previous = window.onInput
        window.onInput = { [weak self] event in
            if case .modifiersChanged(let modifiers) = event { self?.held = ViewportModifiers(modifiers) }
            return previous?(event) ?? false
        }
    }
}

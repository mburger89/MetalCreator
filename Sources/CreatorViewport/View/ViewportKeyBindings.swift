import MetalUI

/// The viewport's keys (spec §9 stopgaps) as MetalUI keymap bindings. The host adds them to its window's
/// `keymap` and routes `onAction` through `handle(_:model:)`.
///
/// MetalUI doesn't focus a `.focusable()` element on click (divergence 94). Until the viewport can take focus, the
/// bindings are window-wide. Pass a `context` once the app shell contributes one (gap M4-a in docs/metalui-gaps.md),
/// so F, + and − still type into text fields.
public enum ViewportKeyBindings {
    public static func bindings(context: String? = nil) -> [KeyBinding] {
        ViewportInputMap.keyBindings.map { KeyBinding($0.spelling, ViewportKeyAction(command: $0.command), context: context) }
    }

    /// Performs a viewport key action. Returns `false` for any other action, so the host can try its own.
    @MainActor
    public static func handle(_ action: any Action, model: ViewportModel) -> Bool {
        guard let key = action as? ViewportKeyAction else { return false }
        model.performKey(key.command)
        return true
    }
}

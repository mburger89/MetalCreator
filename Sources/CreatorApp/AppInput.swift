import CreatorEditor
import CreatorViewport
import MetalUI

/// The window's input hooks for the whole app, installed once for the window's life (spec §9 stopgaps). The
/// document, and with it the editor and its `GraphPanelInput`, is replaced on New and Open, so these hooks
/// forward to whichever is current instead of binding one (as `GraphPanelInput.install(on:)` would):
/// - keymap: the viewport's F, + and − in the `AppKeyContext.viewport` context, so they type into a focused
///   panel field instead (gap M4-a), then the graph's palette arrows and Tab (gaps M5-h, M5-b);
/// - `onAction`: the graph's actions first, then the viewport's keys, except + and − while the pointer is over
///   the graph canvas, which fall through to the graph's own zoom keys (gap M5-f). F has no graph binding, so it
///   frames the viewport from anywhere;
/// - `onInput`: the graph's keys, behind `ViewportModifierTracker`, which only watches modifiers (gap 5);
/// - text focus: `AppModel.releaseTextFocus` clears the window's focus, for canvas and viewport presses (gap M5-g).
@MainActor
public final class AppInput {
    public let model: AppModel
    /// The held modifier keys for the viewport's drags, until MetalUI's drags report them (C7 item 5).
    public let modifiers = ViewportModifierTracker()

    public init(model: AppModel) {
        self.model = model
    }

    /// The window keymap: the viewport's keys (in their context), then the graph panel's.
    public static var keymap: Keymap {
        Keymap(ViewportKeyBindings.bindings(context: AppKeyContext.viewport) + GraphPanelInput.keymap.bindings)
    }

    public func install(on window: Window) {
        window.keymap = Self.keymap
        window.onAction = { [weak self] action in self?.handleAction(action) ?? false }
        window.onInput = { [weak self] event in self?.handleInput(event) ?? false }
        modifiers.install(on: window)
        model.releaseTextFocus = { [weak window] in window?.focus(nil) }
    }

    /// A keymap action. Unclaimed (`false`), MetalUI passes the key on as if it were unbound.
    public func handleAction(_ action: any Action) -> Bool {
        if model.graphInput.handleAction(action) { return true }
        guard let key = action as? ViewportKeyAction else { return false }
        if key.command != .frame, model.editor.pointerLocation != nil { return false }
        return ViewportKeyBindings.handle(key, model: model.viewport)
    }

    /// The window's input fallback: the keys no focused field claimed.
    public func handleInput(_ event: InputEvent) -> Bool {
        model.graphInput.handle(event)
    }
}

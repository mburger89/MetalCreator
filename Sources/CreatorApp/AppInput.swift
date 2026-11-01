import CreatorEditor
import CreatorViewport
import MetalUI

/// The window's input hooks for the whole app, installed once for the window's life (spec §9 stopgaps). The
/// document, and with it the editor and its `GraphPanelInput`, is replaced on New and Open, so these hooks
/// forward to whichever is current instead of binding one (as `GraphPanelInput.install(on:)` would):
/// - keymap: the viewport's F, + and − in the `AppKeyContext.viewport` context, so they type into a focused
///   panel field instead (gap M4-a), then the graph's palette arrows (gap M5-h);
/// - `onAction`: the graph's actions first, then the viewport's keys, except while the pointer is over the graph
///   canvas: there F, + and − fall through to the graph's own keys (F frames the graph's selection, + and − zoom
///   the canvas; spec 2026-10-09 §3). The graph's keys are scoped by MetalUI C9 (the canvas is a key region whose
///   `onKeyPress` runs them), so this veto is only the viewport's side of M4-a, left until the viewport adopts C9;
/// - `onInput`: the open palette's keys and its click-outside.
///
/// Giving the keys back from a text field on a press is not here: `AppWindowRoot` resigns focus on any primary press
/// (MetalUI C24, gap CT-a), the canvas's key region having done it for the canvas alone before (gap M5-g).
@MainActor
public final class AppInput {
    public let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    /// The window keymap: the viewport's keys (in their context), then the graph panel's.
    public static var keymap: Keymap {
        Keymap(ViewportKeyBindings.bindings(context: AppKeyContext.viewport)
            + [KeyBinding("d", ModelDimensionKeyAction(), context: AppKeyContext.viewport),
               KeyBinding("m", MeasureKeyAction(), context: AppKeyContext.viewport),
            ]
            + GraphPanelInput.keymap.bindings)
    }

    public func install(on window: Window) {
        window.keymap = Self.keymap
        window.onAction = { [weak self] action in self?.handleAction(action) ?? false }
        window.onInput = { [weak self] event in self?.handleInput(event) ?? false }
    }

    /// A keymap action. Unclaimed (`false`), MetalUI passes the key on as if it were unbound.
    public func handleAction(_ action: any Action) -> Bool {
        if model.graphInput.handleAction(action) { return true }
        if action is ModelDimensionKeyAction {
            if model.editor.pointerLocation != nil { return false }
            return model.beginModelDimension()
        }
        if action is MeasureKeyAction {
            if model.editor.pointerLocation != nil || model.sketch != nil { return false }
            let starting = model.measure == nil
            model.setMeasure(starting)
            return starting ? model.measure != nil : true
        }
        guard let key = action as? ViewportKeyAction else { return false }
        if model.editor.pointerLocation != nil { return false }
        return ViewportKeyBindings.handle(key, model: model.viewport)
    }

    /// The window's input fallback: the keys no focused field claimed.
    public func handleInput(_ event: InputEvent) -> Bool {
        model.graphInput.handle(event)
    }
}

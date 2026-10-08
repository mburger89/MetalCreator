import CreatorGeometry
import MetalUI

/// The graph panel's stopgap input bindings (spec §9), in one place so MetalUI's C7 APIs can
/// replace them locally (docs/metalui-gaps.md). Each C7 stand-in is one function named after the
/// provisional C7 API it waits for, so the swap stays in this file (and its test):
/// - `spatialTapGesture()` (C7 `SpatialTapGesture`, gap 4): a click's location comes from a
///   `DragGesture(minimumDistance: 0)` that ends where it began. Its swap changes the return type,
///   so `canvasGesture()` then splits into a tap plus a drag with a nonzero minimum distance.
/// - `dragValueModifiers(_:)` (C7 `DragGesture.Value.modifiers`, gap 5): the modifiers held during
///   a press, tracked meanwhile from the window's `.modifiersChanged` and key events in `handle(_:)`.
///   Its swap is body-only.
/// - Scroll and pinch (C7 `.onScrollWheel`, `MagnifyGesture`, gaps 1, 2) have no stand-in: the
///   +/− keys and header zoom buttons (`EditorModel.zoom(in:)`) are the stopgap, and they stay.
///   The canvas sets no cursor yet (C7 `.pointerStyle(_:)`).
///
/// Two more stopgaps are for MetalUI gaps outside C7:
/// - keys: read from the window's `onInput` fallback, so a focused text field keeps its keys;
///   the palette's ↑/↓ alone go through the window keymap (`keymap`, `handleAction`), because a
///   focused field claims arrows before `onInput` (gap M5-h);
/// - focus: a canvas press clears text focus through `releaseTextFocus`, because MetalUI never
///   unfocuses a field on an outside press (gap M5-g).
@MainActor
public final class GraphPanelInput {
    public let model: EditorModel
    /// Clears the window's text focus. The shell sets it to `{ [weak window] in window?.focus(nil) }`.
    /// Without it, an inspector field edited a moment ago keeps claiming Delete, ⌘C/⌘V/⌘Z and
    /// Space while the user works on the canvas.
    public var releaseTextFocus: (@MainActor () -> Void)?

    public init(model: EditorModel) {
        self.model = model
    }

    /// Installs every hook on `window`, composing with the handlers already there. Its `onInput`
    /// side can go on before or after M4's `ViewportModifierTracker.install(on:)`, which chains the
    /// same way. A keymap or `onAction` *assigned* after this call replaces the graph's (M4's
    /// harness assigns both), so the host sets those first, or appends and chains them like this:
    /// - `onInput`: this panel's `handle(_:)` first, then the previous handler. `.modifiersChanged`
    ///   is never claimed, so both trackers see it.
    /// - `keymap`: `keymap`'s bindings are appended to the window's.
    /// - `onAction`: `handleAction(_:)` first, then the previous handler.
    /// - `releaseTextFocus`: `window.focus(nil)`, unless the shell set its own.
    public func install(on window: Window) {
        let previousInput = window.onInput
        window.onInput = { [weak self] event in
            if self?.handle(event) == true { return true }
            return previousInput?(event) ?? false
        }
        window.keymap = Keymap(window.keymap.bindings + Self.keymap.bindings)
        let previousAction = window.onAction
        window.onAction = { [weak self] action in
            if self?.handleAction(action) == true { return true }
            return previousAction?(action) ?? false
        }
        if releaseTextFocus == nil {
            releaseTextFocus = { [weak window] in window?.focus(nil) }
        }
    }

    /// Install as (or merge into) `Window.keymap`, with `handleAction(_:)` in `Window.onAction`.
    public static var keymap: Keymap {
        Keymap {
            KeyBinding("up", PaletteMove(step: -1))
            KeyBinding("down", PaletteMove(step: 1))
        }
    }

    /// Install from `Window.onAction`. Runs a palette move while the palette is open. Otherwise it
    /// returns false, and MetalUI passes the key on (to a focused field) as if it were unbound.
    public func handleAction(_ action: any Action) -> Bool {
        guard let move = action as? PaletteMove, model.palette != nil else { return false }
        model.movePaletteHighlight(by: move.step)
        return true
    }

    /// Install from `Window.onInput` (`install(on:)` does). Returns true when the event was used.
    /// Tracking modifiers here is part of the `dragValueModifiers(_:)` stopgap.
    public func handle(_ event: InputEvent) -> Bool {
        switch event {
        case .modifiersChanged(let modifiers):
            model.modifiers = Self.canvasModifiers(modifiers)
            return false
        case .keyDown(let key):
            model.modifiers = Self.canvasModifiers(key.modifiers)
            guard let command = GraphKeyBindings.command(for: key, paletteOpen: model.palette != nil) else { return false }
            return model.perform(command)
        default:
            return false
        }
    }

    /// The canvas's one press-and-drag gesture: clicks, pans, moves, box selection and wiring.
    public func canvasGesture() -> DragGesture {
        Self.spatialTapGesture()
            .onChanged { [self] value in
                adoptModifiers(of: value)
                canvasChanged(from: Self.vector(value.startLocation), to: Self.vector(value.location))
            }
            .onEnded { [self] value in
                adoptModifiers(of: value)
                canvasEnded(from: Self.vector(value.startLocation), at: Self.vector(value.location))
            }
    }

    /// Stand-in for C7's `SpatialTapGesture` (gap 4). MetalUI reports no tap location, so a click
    /// is a zero-distance drag: it reports a change and an end at the press point. When C7 lands,
    /// a `SpatialTapGesture` carries the clicks and this drag keeps its minimum distance.
    static func spatialTapGesture() -> DragGesture {
        DragGesture(minimumDistance: Pixels(0))
    }

    /// Stand-in for C7's `DragGesture.Value.modifiers` (gap 5): the modifiers held at this change
    /// of the press. Today they are the ones `handle(_:)` tracked from `.modifiersChanged` and key
    /// events. When C7 lands this returns `Self.canvasModifiers(value.modifiers)`, and `handle(_:)`
    /// stops tracking.
    func dragValueModifiers(_ value: DragGesture.Value) -> CanvasModifiers {
        model.modifiers
    }

    /// Writes the press's modifiers into the model only when they changed, so an unchanged set
    /// doesn't invalidate the model's observers on every drag step.
    private func adoptModifiers(of value: DragGesture.Value) {
        let held = dragValueModifiers(value)
        if held != model.modifiers { model.modifiers = held }
    }

    /// The gesture moved. The first call of a press releases text focus.
    func canvasChanged(from start: Vector2, to location: Vector2) {
        if model.currentPress?.point != start { releaseTextFocus?() }
        model.pointerDragged(from: start, to: location)
    }

    /// The gesture ended (a click calls only this, so it releases focus too).
    func canvasEnded(from start: Vector2, at location: Vector2) {
        if model.currentPress?.point != start { releaseTextFocus?() }
        model.pointerReleased(from: start, at: location)
    }

    /// The pointer over the canvas, from `.onContinuousHover`.
    public func hover(_ phase: HoverPhase) {
        switch phase {
        case .active(let point): model.pointerLocation = Self.vector(point)
        case .ended: model.pointerLocation = nil
        }
    }

    public static func canvasModifiers(_ modifiers: Modifiers) -> CanvasModifiers {
        var result: CanvasModifiers = []
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.command) { result.insert(.command) }
        return result
    }

    static func vector(_ point: Point<Pixels>) -> Vector2 {
        Vector2(Double(point.x.value), Double(point.y.value))
    }
}

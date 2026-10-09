import CreatorGeometry
import MetalUI

/// The graph panel's input (spec §9): the canvas's gestures, and the window hooks for the MetalUI gaps C7 didn't
/// close, in one place (docs/metalui-gaps.md). The canvas's pointer input is MetalUI C7's; the behaviour is the
/// model's (`EditorModel+Pointer`), and this type only turns MetalUI values into the model's:
/// - `canvasGesture()`: one `DragGesture(minimumDistance: 0)` carries clicks, pans, moves, box selection and
///   wiring. Its values give the press point (`startLocation`) and the modifiers held at each change
///   (`DragGesture.Value.modifiers`, the press's at the first), so Shift-click and ⇧/⌥-drag read the press's own
///   modifiers, and the model tells a click from a drag (`EditorModel.dragThreshold`). It isn't a
///   `SpatialTapGesture` plus a drag, as the viewport's is: a tap's value has no modifiers, and a click must know
///   whether ⇧ was held (gap GI-a).
/// - `scrolled(_:)`, from the canvas's `.onScrollWheel`: two-finger scroll and the wheel pan, ⌘-scroll zooms
///   about the pointer (`EditorModel.scrolled(by:at:modifiers:phase:)`, phases from `scrollPhase(of:)`).
/// - `pinchGesture()`: a `MagnifyGesture` zooms about where the pinch began (`EditorModel.pinchChanged`).
///
/// Three stopgaps remain, for MetalUI gaps outside C7:
/// - keys: read from the window's `onInput` fallback, so a focused text field keeps its keys;
///   the palette's ↑/↓ and Tab over the canvas alone go through the window keymap (`keymap`,
///   `handleAction`), because a focused field claims arrows and focus traversal claims Tab before
///   `onInput` (gaps M5-h, M5-b), and keys aren't scoped to an element until MetalUI C9;
/// - focus: a canvas press clears text focus through `releaseTextFocus`, because MetalUI never
///   unfocuses a field on an outside press (gap M5-g);
/// - the floating palette's "click outside": a press of any button reaching `onInput` outside the
///   palette closes it (`handle(_:)`), because MetalUI's only overlay that dismisses itself is
///   `.popover`, with its own chrome (gap EP-b).
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

    /// Installs every hook on `window`, composing with the handlers already there (`GraphPanelPreview` uses it;
    /// the app installs `AppInput` instead, which forwards to the current document's `GraphPanelInput`). A keymap
    /// or `onAction` *assigned* after this call replaces the graph's, so the host sets those first, or appends and
    /// chains them like this:
    /// - `onInput`: this panel's `handle(_:)` first, then the previous handler.
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
            KeyBinding("tab", GraphTab())
        }
    }

    /// Install from `Window.onAction`. Runs a palette move while the palette is open, and opens the
    /// palette on Tab while the pointer is over the visible canvas and no palette is open. Otherwise
    /// it returns false, and MetalUI passes the key on (to a focused field, Tab focus traversal, a
    /// `GraphShowButton` shortcut or `onInput`) as if it were unbound.
    public func handleAction(_ action: any Action) -> Bool {
        switch action {
        case let move as PaletteMove:
            guard model.palette != nil else { return false }
            model.movePaletteHighlight(by: move.step)
            return true
        case is GraphTab:
            guard model.isPanelVisible, model.pointerLocation != nil, model.palette == nil else { return false }
            model.openPalette()
            return true
        default:
            return false
        }
    }

    /// Install from `Window.onInput` (`install(on:)` does). Returns true when the event was used: the graph's
    /// keys. Every primary press reaches `onInput` (MetalUI claims none, except one in a text field or on a
    /// slider), and so does every other button's press but a right-click that opens a context menu, so the
    /// floating palette's "click outside" is read here too. Modifier changes aren't tracked: a press reads its
    /// own (`canvasGesture()`).
    public func handle(_ event: InputEvent) -> Bool {
        switch event {
        case .keyDown(let key):
            guard let command = GraphKeyBindings.command(for: key, paletteOpen: model.palette != nil) else { return false }
            return model.perform(command)
        case .mouseDown(let mouse), .rightMouseDown(let mouse), .otherMouseDown(let mouse):
            // Any button's press outside the floating palette closes it. Never claimed, so the press goes on.
            model.windowPressed(at: Self.vector(mouse.position))
            return false
        default:
            return false
        }
    }

    /// The canvas's one press-and-drag gesture: clicks, pans, moves, box selection and wiring. A zero minimum
    /// distance, so its first change is the press itself, with the press's modifiers.
    public func canvasGesture() -> DragGesture {
        DragGesture(minimumDistance: Pixels(0))
            .onChanged { [self] value in canvasChanged(value) }
            .onEnded { [self] value in canvasEnded(value) }
    }

    /// The gesture moved (its first change is the press). The first call of a press releases text focus.
    func canvasChanged(_ value: DragGesture.Value) {
        let start = Self.vector(value.startLocation)
        if model.currentPress?.point != start { releaseTextFocus?() }
        model.pointerDragged(from: start, to: Self.vector(value.location), modifiers: Self.canvasModifiers(value.modifiers))
    }

    /// The gesture ended: a release, or a click's only report when no change came first, so it releases focus too.
    func canvasEnded(_ value: DragGesture.Value) {
        let start = Self.vector(value.startLocation)
        if model.currentPress?.point != start { releaseTextFocus?() }
        model.pointerReleased(from: start, at: Self.vector(value.location), modifiers: Self.canvasModifiers(value.modifiers))
    }

    /// A scroll over the canvas, from its `.onScrollWheel`: the delta, the pointer in canvas-local points, the
    /// modifiers and the phase go to the model. Returns `true` (claimed), so the viewport beneath never sees it.
    public func scrolled(_ event: ScrollEvent) -> Bool {
        model.scrolled(by: Self.vector(event.delta), at: Self.vector(event.location),
                       modifiers: Self.canvasModifiers(event.modifiers), phase: Self.scrollPhase(of: event))
    }

    /// The canvas's pinch: zooms by the cumulative magnification about where it began (`startLocation`).
    public func pinchGesture() -> MagnifyGesture {
        MagnifyGesture()
            .onChanged { [model] value in
                model.pinchChanged(magnification: value.magnification, centre: Self.vector(value.startLocation))
            }
            .onEnded { [model] _ in model.pinchEnded() }
    }

    /// A MetalUI scroll event's place in its gesture. Momentum wins over the gesture phase, and its end (or
    /// cancellation) is its own phase; no phase at all is a wheel step (and every scroll on SDL, which reports none,
    /// MetalUI `CI-I` item 6).
    public static func scrollPhase(of event: ScrollEvent) -> CanvasScrollPhase {
        if event.isMomentum {
            return event.momentumPhase == .ended || event.momentumPhase == .cancelled ? .momentumEnded : .momentum
        }
        switch event.phase {
        case .none: return .step
        case .mayBegin, .began: return .began
        case .changed: return .changed
        case .ended, .cancelled: return .ended
        }
    }

    /// A node-library row's one gesture: a zero-distance drag reported in window points (`.global`), so a click
    /// and a drag are told apart by the model (`EditorModel.moveLibraryDrag`, `endLibraryDrag`, `LibraryDrag.threshold`)
    /// and the release is turned into a canvas point with the host's placement (`canvasFrameInWindow`), with no
    /// row frame needed. MetalUI's own gesture: the drag never leaves the window as a system drag.
    public func libraryGesture(for typeID: String) -> DragGesture {
        DragGesture(minimumDistance: Pixels(0), coordinateSpace: .global)
            .onChanged { [model] value in
                model.moveLibraryDrag(typeID, from: Self.vector(value.startLocation), to: Self.vector(value.location))
            }
            .onEnded { [model] value in
                model.endLibraryDrag(typeID, from: Self.vector(value.startLocation), at: Self.vector(value.location))
            }
    }

    /// The pointer over the canvas, from `.onContinuousHover`.
    public func hover(_ phase: HoverPhase) {
        switch phase {
        case .active(let point): model.pointerLocation = Self.vector(point)
        case .ended: model.pointerLocation = nil
        }
    }

    /// The canvas's modifiers from MetalUI's. Control isn't one: the canvas binds nothing to it.
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

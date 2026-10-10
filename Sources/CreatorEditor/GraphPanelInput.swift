import CreatorGeometry
import MetalUI

/// The graph panel's input (spec §9): the canvas's gestures, and the window hooks for the MetalUI gaps C7 didn't
/// close, in one place (docs/metalui-gaps.md). The canvas's pointer input is MetalUI C7's; the behaviour is the
/// model's (`EditorModel+Pointer`), and this type only turns MetalUI values into the model's:
/// - `canvasGesture()`: one `DragGesture(minimumDistance: 0)` carries clicks, moves, box selection and
///   wiring. Its values give the press point (`startLocation`) and the modifiers held at each change
///   (`DragGesture.Value.modifiers`, the press's at the first), so Shift-click and ⇧/⌥-drag read the press's own
///   modifiers, and the model tells a click from a drag (`EditorModel.dragThreshold`). It isn't a
///   `SpatialTapGesture` plus a drag, as the viewport's is: a tap's value has no modifiers, and a click must know
///   whether ⇧ was held (gap GI-a).
/// - `middlePanGesture()`: a `DragGesture(minimumDistance: 0, button: .middle)` pans (`EditorModel.middleDragged`),
///   in the middle button's own arena (MetalUI `CI-F`), as the viewport's middle drag does (VC3). A plain drag
///   box-selects (the user's Gate G answer (b), 2026-10-09), so this and two-finger scroll are the canvas's pans.
/// - `scrolled(_:)`, from the canvas's `.onScrollWheel`: two-finger scroll and the wheel pan, ⌘-scroll zooms
///   about the pointer (`EditorModel.scrolled(by:at:modifiers:phase:)`, phases from `scrollPhase(of:)`).
/// - `pinchGesture()`: a `MagnifyGesture` zooms about where the pinch began (`EditorModel.pinchChanged`).
/// - The cursor is the model's (`EditorModel.canvasCursor`, a closed hand while a middle drag pans); `GraphCanvas`
///   sets it.
///
/// The canvas's keys and its text focus are MetalUI C9's (key and focus scoping), not stopgaps:
/// - `keyPressed(_:)`, from the canvas surface's `.onKeyPress` (`CanvasSurface`): the graph's keys. The surface is a
///   `hoverKeyRegion`, so with nothing focused the keys go to the canvas under the pointer, and a focused field (the
///   inspector's, the library's search, the canvas's own comment editor) keeps every key, wherever the pointer is
///   (gap M5-b). A press on the canvas also clears a field's focus (gap M5-g).
///
/// Two stopgaps remain, for MetalUI gaps C9 did not close:
/// - the palette's keys: its ↑/↓ and the keys of the open palette's search field go through the window keymap
///   (`keymap`, `handleAction`) and `onInput` (`handle(_:)`), because a focused single-line field claims arrows before
///   `onInput` (gap M5-h, which C9 answers with `onKeyPress` on the field; not adopted here);
/// - the floating palette's "click outside": a press of any button reaching `onInput` outside the
///   palette closes it (`handle(_:)`), because MetalUI's only overlay that dismisses itself is
///   `.popover`, with its own chrome (gap EP-b).
@MainActor
public final class GraphPanelInput {
    public let model: EditorModel

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
    }

    /// Install as (or merge into) `Window.keymap`, with `handleAction(_:)` in `Window.onAction`.
    public static var keymap: Keymap {
        Keymap {
            KeyBinding("up", PaletteMove(step: -1))
            KeyBinding("down", PaletteMove(step: 1))
        }
    }

    /// Install from `Window.onAction`. Runs a palette move while the palette is open. Otherwise it returns false, and
    /// MetalUI passes the key on (to a focused field, Tab focus traversal, a `GraphShowButton` shortcut or `onInput`)
    /// as if it were unbound.
    public func handleAction(_ action: any Action) -> Bool {
        guard let move = action as? PaletteMove, model.palette != nil else { return false }
        model.movePaletteHighlight(by: move.step)
        return true
    }

    /// Install from `Window.onInput` (`install(on:)` does). Returns true when the event was used: the open palette's keys
    /// (the rest of the graph's keys are `keyPressed(_:)`'s, scoped by MetalUI C9). Every primary press reaches
    /// `onInput` (MetalUI claims none, except one in a text field or on a slider), and so does every other button's
    /// press but a right-click that opens a context menu, so the floating palette's "click outside" is read here too.
    /// Modifier changes aren't tracked: a press reads its own (`canvasGesture()`).
    public func handle(_ event: InputEvent) -> Bool {
        switch event {
        case .keyDown(let key):
            guard model.palette != nil, let command = GraphKeyBindings.command(for: key, paletteOpen: true) else { return false }
            return model.perform(command)
        case .mouseDown(let mouse), .rightMouseDown(let mouse), .otherMouseDown(let mouse):
            // Any button's press outside the floating palette closes it. Never claimed, so the press goes on.
            model.windowPressed(at: Self.vector(mouse.position))
            return false
        default:
            return false
        }
    }

    /// The graph's keys, from the canvas surface's `onKeyPress` (MetalUI C9: the surface is a key region, so these
    /// arrive only while the pointer is over the canvas and nothing is focused; a focused
    /// field anywhere keeps its keys). `.handled` claims the key, `.ignored` lets it go on (the palette's own keys are
    /// `handle(_:)`'s, and Tab only counts over the canvas: unclaimed it moves focus).
    public func keyPressed(_ press: KeyPress) -> KeyPress.Result {
        let key = Self.keyEvent(key: press.key, characters: press.characters, modifiers: press.modifiers,
                                isRepeat: press.phase.contains(.repeat))
        return handleKey(key) ? .handled : .ignored
    }

    /// The `KeyEvent` the graph's bindings read, from a `KeyPress`'s parts. `KeyPress.key` is the first character the
    /// unmodified layout reports (`KeyEquivalent` spells the arrows, Delete, Tab, Return and Esc as AppKit's
    /// characters, which `GraphKeyBindings` matches); `isRepeat` is what splits a held arrow's nudges from a new step.
    /// Pure, so the mapping is tested without a window. The timestamp is unused by the bindings.
    public static func keyEvent(key: KeyEquivalent, characters: String, modifiers: EventModifiers, isRepeat: Bool) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: String(key.character), characters: characters, modifiers: modifiers,
                 isRepeat: isRepeat, timestamp: 0)
    }

    /// Runs the graph's command for `key`, if it has one and the palette isn't open. Returns whether it was used.
    public func handleKey(_ key: KeyEvent) -> Bool {
        guard model.palette == nil, let command = GraphKeyBindings.command(for: key, paletteOpen: false) else { return false }
        // Tab opens the palette at the pointer; with the pointer not reported over the canvas it is focus traversal's.
        if command == .tab, model.pointerLocation == nil { return false }
        return model.perform(command)
    }

    /// The canvas's one press-and-drag gesture: clicks, moves, box selection and wiring. A zero minimum
    /// distance, so its first change is the press itself, with the press's modifiers.
    public func canvasGesture() -> DragGesture {
        DragGesture(minimumDistance: Pixels(0))
            .onChanged { [self] value in canvasChanged(value) }
            .onEnded { [self] value in canvasEnded(value) }
    }

    /// The gesture moved (its first change is the press). A press also clears a focused field's focus, because the
    /// canvas surface is a key region (MetalUI C9, gap M5-g).
    func canvasChanged(_ value: DragGesture.Value) {
        let start = Self.vector(value.startLocation)
        model.pointerDragged(from: start, to: Self.vector(value.location), modifiers: Self.canvasModifiers(value.modifiers))
    }

    /// The gesture ended: a release, or a click's only report when no change came first.
    func canvasEnded(_ value: DragGesture.Value) {
        let start = Self.vector(value.startLocation)
        model.pointerReleased(from: start, at: Self.vector(value.location), modifiers: Self.canvasModifiers(value.modifiers))
    }

    /// The canvas's middle-button drag: pans. A zero minimum distance, so the closed hand shows from the press (a
    /// middle press never clicks). Text focus is left alone: a pan isn't a click on the canvas.
    public func middlePanGesture() -> DragGesture {
        DragGesture(minimumDistance: Pixels(0), button: .middle)
            .onChanged { [self] value in middleChanged(value) }
            .onEnded { [self] value in middleEnded(value) }
    }

    /// The middle drag moved (its first change is the press).
    func middleChanged(_ value: DragGesture.Value) {
        model.middleDragged(from: Self.vector(value.startLocation), to: Self.vector(value.location))
    }

    /// The middle button was released.
    func middleEnded(_ value: DragGesture.Value) {
        model.middleReleased(from: Self.vector(value.startLocation), at: Self.vector(value.location))
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

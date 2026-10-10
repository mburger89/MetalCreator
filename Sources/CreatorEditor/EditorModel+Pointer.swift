import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

extension EditorModel {
    /// How far a press must move before it counts as a drag, in screen points.
    public static let dragThreshold = 3.0

    /// A canvas drag moved. `start` and `location` are canvas-local screen points, and `modifiers` are the ones
    /// held at this change (MetalUI's `DragGesture.Value.modifiers`). The first call of a press records what it
    /// landed on and the modifiers held at the press; a drag starts once it moves `dragThreshold`, and the
    /// modifiers held then decide what it does (on empty canvas the box's mode: none replaces, ⇧ adds, ⌘ toggles;
    /// ⌥ duplicates the selection).
    public func pointerDragged(from start: Vector2, to location: Vector2, modifiers: CanvasModifiers = []) {
        ensurePress(at: start, modifiers: modifiers)
        guard let press = currentPress, !isPressCancelled else { return }
        if interaction == nil {
            guard (location - press.point).length >= Self.dragThreshold else { return }
            setInteraction(beginInteraction(for: press.hit, at: press.point, modifiers: modifiers))
        }
        update(to: location, from: press.point)
    }

    /// The press ended at `location`. Without a drag this is a click, which selects by the modifiers held at the
    /// press (`SelectionMode`). `modifiers` (held at the release) count only for a press that reported no change before.
    public func pointerReleased(from start: Vector2, at location: Vector2, modifiers: CanvasModifiers = []) {
        ensurePress(at: start, modifiers: modifiers)
        guard let press = currentPress, !isPressCancelled else {
            // A press whose drag Esc cancelled ends here: no click, no wire.
            endPress()
            return
        }
        switch interaction {
        case nil: click(press.hit, mode: SelectionMode(press.modifiers))
        case .moving: document.endCoalescing()
        case .duplicating(let start, let delta): finishDuplicate(start: start, delta: delta)
        case .connecting(let wire): finishWire(wire, at: location)
        case .boxSelecting(let start, _, let base, let mode):
            applyBox(from: start, to: transform.toCanvas(location), base: base, mode: mode)
        case .panning: break
        }
        endPress()
    }

    /// A press began, with `modifiers` held. Commits a typed inspector value, ends any slider drag's undo step and
    /// closes the palette. A middle-button pan under way ends: the primary button always gets its drag (MetalUI
    /// `CI-F` item 3), and the rest of that middle press is ignored (`middleDragged`).
    public func pointerPressed(at screen: Vector2, modifiers: CanvasModifiers = []) {
        commitPendingEntry()
        document.endCoalescing()
        palette = nil
        if case .panning? = interaction { setInteraction(nil) }
        beginPress(at: screen, modifiers: modifiers)
    }

    /// Esc during a drag (spec 2026-10-09 §3). A drag that hasn't changed the document is cancelled and the rest of
    /// its press ignored: a wire being dragged is dropped, ⌥-drag ghosts vanish, and a box puts back the selection it
    /// began with. A pan (the middle button's) or a move goes on (a move's steps are already in the document, for
    /// Undo), and the key is still claimed so it can't clear the selection mid-drag. Returns false with no drag under
    /// way.
    func cancelInteraction() -> Bool {
        switch interaction {
        case nil: return false
        case .panning?, .moving?: return true
        case .connecting?, .duplicating?: break
        case .boxSelecting(_, _, let base, _)?: canvasSelection = base
        }
        cancelPress()
        return true
    }

    /// Starts a press at `start` unless one with that start is in progress. A recorded press
    /// with another start is a gesture that never ended (say the window lost key status
    /// mid-drag); it is dropped, so its hit, modifiers and interaction don't leak into this one.
    private func ensurePress(at start: Vector2, modifiers: CanvasModifiers) {
        guard currentPress?.point != start else { return }
        if currentPress != nil { endPress() }
        pointerPressed(at: start, modifiers: modifiers)
    }

    /// A press that didn't move selects what it landed on as `mode` says (spec 2026-10-09 §3). On an item already
    /// selected, a plain click collapses the selection to it, ⌘ toggles it out and ⇧ keeps it. On empty canvas a
    /// plain click clears the selection and a modified one keeps it.
    private func click(_ hit: CanvasHit, mode: SelectionMode) {
        guard let items = items(for: hit) else {
            if mode == .replace { clearSelection() }
            return
        }
        select(items, mode: mode)
    }

    private func beginInteraction(for hit: CanvasHit, at screen: Vector2, modifiers: CanvasModifiers) -> CanvasInteraction {
        if case .socket(let socket) = hit {
            return .connecting(WireDrag(from: socket, current: transform.toCanvas(screen)))
        }
        // Any other hit reaches the selection only through `items(for:)`, so a new kind of hit (sub-project B's
        // comments) needs no change here. An unselected item is selected first: alone, or added with ⇧ or ⌘.
        guard let items = items(for: hit) else { return emptyCanvasDrag(at: screen, modifiers: modifiers) }
        if !canvasSelection.isSuperset(of: items) {
            select(items, mode: SelectionMode(modifiers) == .replace ? .replace : .add)
        }
        // Every selected item moves (with ⌥, is copied once the pointer has moved), so a ⌘-drag on a selected
        // node moves the selection instead of toggling the node.
        let start = positions(of: canvasSelection)
        if modifiers.contains(.option) { return .duplicating(start: start, delta: .zero) }
        return .moving(start: start, key: "move-\(UUID().uuidString)")
    }

    /// A drag that began on empty canvas box-selects (the user's Gate G answer (b), 2026-10-09), in the mode the
    /// modifiers held as it crosses `dragThreshold` ask for: none replaces the selection, ⇧ adds, ⌘ toggles. It never
    /// pans: the middle button (`middleDragged`) and two-finger scroll do.
    private func emptyCanvasDrag(at screen: Vector2, modifiers: CanvasModifiers) -> CanvasInteraction {
        let point = transform.toCanvas(screen)
        return .boxSelecting(start: point, current: point, base: canvasSelection, mode: SelectionMode(modifiers))
    }

    private func update(to location: Vector2, from pressPoint: Vector2) {
        guard let interaction else { return }
        // Screen delta → stored (left-to-right) canvas delta: undo the zoom, then the dock transpose.
        let storedDelta = flow.stored((location - pressPoint) * (1 / transform.zoom))
        switch interaction {
        case .panning(let startOffset):
            transform = CanvasTransform(offset: startOffset + (location - pressPoint), zoom: transform.zoom)
        case .moving(let start, let key):
            try? document.perform(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key)
        case .duplicating(let start, _):
            setInteraction(.duplicating(start: start, delta: storedDelta))
        case .boxSelecting(let start, _, let base, let mode):
            applyBox(from: start, to: transform.toCanvas(location), base: base, mode: mode)
        case .connecting(var wire):
            wire.current = transform.toCanvas(location)
            setInteraction(.connecting(wire))
        }
    }

    /// The box from `start` to `current` (display canvas points) combined with the selection the drag began with, as
    /// `mode` says (none replaces, ⇧ adds, ⌘ toggles). It starts from `base` at every step, so a node the box covers
    /// and then leaves again is as it was.
    private func applyBox(from start: Vector2, to current: Vector2, base: CanvasSelection, mode: SelectionMode) {
        setInteraction(.boxSelecting(start: start, current: current, base: base, mode: mode))
        canvasSelection = base.applying(items(intersecting: CanvasRect(corner: start, current)), mode: mode)
    }

    /// The copies land where the ghosts were, as one undo step; the originals never moved.
    private func finishDuplicate(start: SelectionPositions, delta: Vector2) {
        if let copies = insert(clipboard(of: start.items), offset: delta) { canvasSelection = copies }
    }

    private func finishWire(_ wire: WireDrag, at location: Vector2) {
        guard case .socket(let target) = hitTest(location) else {
            // Dragging a wired input off onto empty canvas removes its wire.
            if wire.from.isInput, let link = graph.incomingLink(to: wire.from.endpoint) {
                do {
                    try document.perform(.disconnect(link))
                } catch {
                    refuse(error.message, node: link.to.node)
                }
            }
            return
        }
        guard target.isInput != wire.from.isInput else {
            refuse("Connect an output to an input.", node: target.endpoint.node)
            return
        }
        let output = wire.from.isInput ? target.endpoint : wire.from.endpoint
        let input = wire.from.isInput ? wire.from.endpoint : target.endpoint
        connect(Link(from: output, to: input))
    }
}

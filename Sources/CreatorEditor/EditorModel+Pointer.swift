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
    /// modifiers held then decide what it does (⇧ box-selects on empty canvas, ⌥ duplicates nodes).
    public func pointerDragged(from start: Vector2, to location: Vector2, modifiers: CanvasModifiers = []) {
        ensurePress(at: start, modifiers: modifiers)
        guard let press = currentPress else { return }
        if interaction == nil {
            guard (location - press.point).length >= Self.dragThreshold else { return }
            setInteraction(beginInteraction(for: press.hit, at: press.point, modifiers: modifiers))
        }
        update(to: location, from: press.point)
    }

    /// The press ended at `location`. Without a drag this is a click, and ⇧ held at the press extends the
    /// selection. `modifiers` (held at the release) count only for a press that reported no change before.
    public func pointerReleased(from start: Vector2, at location: Vector2, modifiers: CanvasModifiers = []) {
        ensurePress(at: start, modifiers: modifiers)
        guard let press = currentPress else { return }
        switch interaction {
        case nil: click(press.hit, mode: SelectionMode(press.modifiers))
        case .moving: document.endCoalescing()
        case .duplicating(let start, let delta): finishDuplicate(start: start, delta: delta)
        case .connecting(let wire): finishWire(wire, at: location)
        case .panning, .boxSelecting: break
        }
        endPress()
    }

    /// A press began, with `modifiers` held. Commits a typed inspector value, ends any slider drag's undo step and
    /// closes the palette.
    public func pointerPressed(at screen: Vector2, modifiers: CanvasModifiers = []) {
        commitPendingEntry()
        document.endCoalescing()
        palette = nil
        beginPress(at: screen, modifiers: modifiers)
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

    /// A drag that began on empty canvas: ⇧ held as it starts box-selects; otherwise it pans.
    private func emptyCanvasDrag(at screen: Vector2, modifiers: CanvasModifiers) -> CanvasInteraction {
        if modifiers.contains(.shift) {
            let point = transform.toCanvas(screen)
            return .boxSelecting(start: point, current: point, base: selection)
        }
        return .panning(startOffset: transform.offset)
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
        case .boxSelecting(let start, _, let base):
            let current = transform.toCanvas(location)
            setInteraction(.boxSelecting(start: start, current: current, base: base))
            selection = base.union(nodes(intersecting: CanvasRect(corner: start, current)))
        case .connecting(var wire):
            wire.current = transform.toCanvas(location)
            setInteraction(.connecting(wire))
        }
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

import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

extension EditorModel {
    /// How far a press must move before it counts as a drag, in screen points.
    public static let dragThreshold = 3.0

    /// A canvas drag moved. `start` and `location` are canvas-local screen points. The first
    /// call of a press records what it landed on; a drag starts once it moves `dragThreshold`.
    public func pointerDragged(from start: Vector2, to location: Vector2) {
        ensurePress(at: start)
        guard let press = currentPress else { return }
        if interaction == nil {
            guard (location - press.point).length >= Self.dragThreshold else { return }
            setInteraction(beginInteraction(for: press.hit, at: press.point))
        }
        update(to: location, from: press.point)
    }

    /// The press ended at `location`. Without a drag this is a click.
    public func pointerReleased(from start: Vector2, at location: Vector2) {
        ensurePress(at: start)
        guard let press = currentPress else { return }
        switch interaction {
        case nil: click(press.hit)
        case .moving: document.endCoalescing()
        case .duplicating(let start, let delta): finishDuplicate(start: start, delta: delta)
        case .connecting(let wire): finishWire(wire, at: location)
        case .panning, .boxSelecting: break
        }
        endPress()
    }

    /// A press began. Commits a typed inspector value, ends any slider drag's undo step and closes the palette.
    public func pointerPressed(at screen: Vector2) {
        commitPendingEntry()
        document.endCoalescing()
        palette = nil
        beginPress(at: screen)
    }

    /// Starts a press at `start` unless one with that start is in progress. A recorded press
    /// with another start is a gesture that never ended (say the window lost key status
    /// mid-drag); it is dropped, so its hit and interaction don't leak into this one.
    private func ensurePress(at start: Vector2) {
        guard currentPress?.point != start else { return }
        if currentPress != nil { endPress() }
        pointerPressed(at: start)
    }

    private func click(_ hit: CanvasHit) {
        let extending = modifiers.contains(.shift)
        let clicked: NodeID?
        switch hit {
        case .node(let id): clicked = id
        case .socket(let socket): clicked = socket.endpoint.node
        case .empty: clicked = nil
        }
        guard let clicked else {
            if !extending { selection = [] }
            return
        }
        if !extending {
            selection = [clicked]
        } else if selection.contains(clicked) {
            selection.remove(clicked)
        } else {
            selection.insert(clicked)
        }
    }

    private func beginInteraction(for hit: CanvasHit, at screen: Vector2) -> CanvasInteraction {
        switch hit {
        case .socket(let socket):
            return .connecting(WireDrag(from: socket, current: transform.toCanvas(screen)))
        case .node(let id):
            if !selection.contains(id) {
                selection = modifiers.contains(.shift) ? selection.union([id]) : [id]
            }
            let start = Dictionary(uniqueKeysWithValues: selection.compactMap { id in
                graph.nodes[id].map { (id, $0.position) }
            })
            if modifiers.contains(.option) { return .duplicating(start: start, delta: .zero) }
            return .moving(start: start, key: "move-\(UUID().uuidString)")
        case .empty:
            if modifiers.contains(.shift) {
                let point = transform.toCanvas(screen)
                return .boxSelecting(start: point, current: point, base: selection)
            }
            return .panning(startOffset: transform.offset)
        }
    }

    private func update(to location: Vector2, from pressPoint: Vector2) {
        guard let interaction else { return }
        // Screen delta → stored (left-to-right) canvas delta: undo the zoom, then the dock transpose.
        let storedDelta = flow.stored((location - pressPoint) * (1 / transform.zoom))
        switch interaction {
        case .panning(let startOffset):
            transform = CanvasTransform(offset: startOffset + (location - pressPoint), zoom: transform.zoom)
        case .moving(let start, let key):
            let moves = start.keys.sorted().compactMap { id in
                start[id].map { GraphCommand.move(id, to: $0 + storedDelta) }
            }
            try? document.perform(.batch(moves), coalescingKey: key)
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
    private func finishDuplicate(start: [NodeID: Vector2], delta: Vector2) {
        if let ids = insert(clipboard(of: Set(start.keys)), offset: delta) { selection = ids }
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

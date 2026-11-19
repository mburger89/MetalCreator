import CreatorGeometry
import CreatorKernel
import CreatorViewport

/// A selection being moved: where it was grabbed, how each point stood, and how the pointer maps to a movement.
struct MoveDrag {
    enum Reach {
        /// In the plane through the grabbed point facing the camera: `start` is the ray's hit there.
        case plane(Plane, start: Vector3)
        /// Along an axis line through the grabbed point: `start` is where on the line the pointer's ray was closest.
        case axis(Vector3, start: Double)
        /// Along an axis that points nearly at the camera: the pointer's vertical movement, up being along the axis.
        case vertical(Vector3, startY: Double)
        /// Nowhere (a normal lock with no normal).
        case none
    }

    var grabbed: Vector3
    var startOffsets: [PoleIndex: Vector3]
    var reach: Reach
    var didMove = false
}

/// What a control-net drag does: select by a box, or move the selection.
enum DragMode {
    case box(start: ScreenPoint, toggles: Bool, before: Set<PoleIndex>)
    case move(MoveDrag)
}

extension ControlNetSession {
    /// A drag under way: either a box on empty space or the selection moving.
    struct Drag {
        var mode: DragMode
    }

    /// Past this, an axis is too nearly the view direction for the ray to say where on it the pointer is.
    static let degenerateAxis = 0.95

    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        guard let hit = pole(at: point, projector: projector), let grabbed = position(of: hit) else {
            drag = Drag(mode: .box(start: point, toggles: modifiers.contains(.command), before: selection))
            boxRect = ScreenRect(point, point)
            return true
        }
        guard let reach = reach(at: point, grabbed: grabbed, hit: hit, projector: projector) else { return false }
        if selection.contains(hit) { selection = expanded(selection) } else { selection = group(of: hit) }
        var startOffsets: [PoleIndex: Vector3] = [:]
        for index in selection { startOffsets[index] = offsets[index] ?? .zero }
        drag = Drag(mode: .move(MoveDrag(grabbed: grabbed, startOffsets: startOffsets, reach: reach)))
        return true
    }

    private func reach(at point: ScreenPoint, grabbed: Vector3, hit: PoleIndex, projector: ViewportProjector) -> MoveDrag.Reach? {
        let pose = projector.pose
        guard let lock else {
            let plane = Plane(origin: grabbed, normal: pose.toEye, xAxis: pose.right)
            guard let local = projector.planePoint(under: point, on: plane) else { return nil }
            return .plane(plane, start: plane.point(local))
        }
        let axis: Vector3?
        switch lock {
        case .x: axis = .unitX
        case .y: axis = .unitY
        case .z: axis = .unitZ
        case .normal: axis = net.normal(hit)?.normalized
        }
        guard let axis else { return MoveDrag.Reach.none }
        if abs(axis.dot(pose.toEye)) > Self.degenerateAxis { return .vertical(axis, startY: point.y) }
        guard let start = Self.parameter(on: axis, through: grabbed, at: point, projector: projector) else { return nil }
        return .axis(axis, start: start)
    }

    /// Where on the line `origin + s * axis` the ray under `point` passes closest, as `s`.
    private static func parameter(on axis: Vector3, through origin: Vector3, at point: ScreenPoint,
                                  projector: ViewportProjector) -> Double? {
        guard let ray = projector.ray(through: point) else { return nil }
        let w = origin - ray.origin
        let b = axis.dot(ray.direction)
        let denominator = 1 - b * b
        guard denominator > 1e-9 else { return nil }
        let s = (b * ray.direction.dot(w) - axis.dot(w)) / denominator
        return s.isFinite ? s : nil
    }

    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        guard let drag else { return }
        switch drag.mode {
        case let .box(start, _, _):
            boxRect = ScreenRect(start, point)
        case var .move(move):
            apply(to: point, move: move, projector: projector)
            move.didMove = true
            self.drag = Drag(mode: .move(move))
            events.moved(movedPoles(move), .changed)
        }
    }

    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        guard let drag else { return }
        self.drag = nil
        switch drag.mode {
        case let .box(start, toggles, before):
            boxRect = nil
            let rect = ScreenRect(start, point)
            var inside: Set<PoleIndex> = []
            for i in 0..<net.uCount {
                for j in 0..<net.vCount {
                    let index = PoleIndex(i: i, j: j)
                    if let world = position(of: index), let screen = projector.screenPoint(of: world), rect.contains(screen) {
                        inside.insert(index)
                    }
                }
            }
            let caught = expanded(inside)
            selection = toggles ? before.symmetricDifference(caught) : caught
            applyPendingNet(keeping: [:])
        case let .move(move):
            guard move.didMove else {
                applyPendingNet(keeping: [:])
                return
            }
            apply(to: point, move: move, projector: projector)
            let moved = movedPoles(move)
            events.moved(moved, .ended)
            applyPendingNet(keeping: Dictionary(uniqueKeysWithValues: moved.map { ($0.index, $0.offset) }))
        }
    }

    /// Esc during a drag: the points go back to where they stood and the drag ends; the mode stays. With no drag it is the mode's end.
    func cancel() {
        guard let drag else {
            events.ended()
            return
        }
        self.drag = nil
        boxRect = nil
        if case let .move(move) = drag.mode, move.didMove {
            for (index, offset) in move.startOffsets { offsets[index] = offset }
            events.moved(move.startOffsets.keys.sorted().map { PoleMove(index: $0, offset: move.startOffsets[$0] ?? .zero) }, .cancelled)
            // A net shown while the drag was under way may hold its intermediate offsets: the restored ones win.
            applyPendingNet(keeping: move.startOffsets)
            return
        }
        applyPendingNet(keeping: [:])
    }

    /// Done: the mode ends, whatever is under way.
    func done() {
        drag = nil
        boxRect = nil
        pendingNet = nil
        events.ended()
    }

    private func applyPendingNet(keeping kept: [PoleIndex: Vector3]) {
        guard let pending = pendingNet else { return }
        pendingNet = nil
        var moves = pending.moves.filter { kept[$0.index] == nil }
        moves += kept.map { PoleMove(index: $0.key, offset: $0.value) }
        showNet(pending.net, moves: moves)
    }

    private func movedPoles(_ move: MoveDrag) -> [PoleMove] {
        move.startOffsets.keys.sorted().map { PoleMove(index: $0, offset: offsets[$0] ?? .zero) }
    }

    private func apply(to point: ScreenPoint, move: MoveDrag, projector: ViewportProjector) {
        let delta: Vector3
        switch move.reach {
        case let .plane(plane, start):
            guard let local = projector.planePoint(under: point, on: plane) else { return }
            delta = plane.point(local) - start
        case let .axis(axis, start):
            guard let now = Self.parameter(on: axis, through: move.grabbed, at: point, projector: projector) else { return }
            delta = axis * (now - start)
        case let .vertical(axis, startY):
            delta = axis * ((startY - point.y) * projector.millimetresPerPoint)
        case .none:
            delta = .zero
        }
        for (index, start) in move.startOffsets { offsets[index] = start + delta }
    }
}

import CreatorGeometry
import CreatorKernel
import CreatorViewport

/// What a control-net drag does: select by a box, or move the selection.
enum DragMode {
    case box(start: ScreenPoint, toggles: Bool, before: Set<PoleIndex>)
    case move(plane: Plane, startPoint: Vector2, startOffsets: [PoleIndex: Vector3], axis: Vector3?)
}

extension ControlNetSession {
    /// A drag under way: either a box on empty space or the selection moving.
    struct Drag {
        var mode: DragMode
    }

    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        guard let hit = pole(at: point, projector: projector), let grabbed = position(of: hit) else {
            drag = Drag(mode: .box(start: point, toggles: modifiers.contains(.command), before: selection))
            boxRect = ScreenRect(point, point)
            return true
        }
        if !selection.contains(hit) { selection = [hit] }
        let pose = projector.pose
        let plane = Plane(origin: grabbed, normal: pose.toEye, xAxis: pose.right)
        guard let start = projector.planePoint(under: point, on: plane) else { return false }
        let axis: Vector3?
        switch lock {
        case nil: axis = nil
        case .x?: axis = .unitX
        case .y?: axis = .unitY
        case .z?: axis = .unitZ
        case .normal?: axis = net.normal(hit)?.normalized
        }
        var startOffsets: [PoleIndex: Vector3] = [:]
        for index in selection { startOffsets[index] = offsets[index] ?? .zero }
        drag = Drag(mode: .move(plane: plane, startPoint: start, startOffsets: startOffsets, axis: lock == nil ? nil : (axis ?? .zero)))
        return true
    }

    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        guard let drag else { return }
        switch drag.mode {
        case let .box(start, _, _):
            boxRect = ScreenRect(start, point)
        case let .move(plane, startPoint, startOffsets, axis):
            apply(to: point, plane: plane, startPoint: startPoint, startOffsets: startOffsets, axis: axis, projector: projector)
            events.moved(startOffsets.keys.sorted().map { PoleMove(index: $0, offset: offsets[$0] ?? .zero) }, .changed)
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
            selection = toggles ? before.symmetricDifference(inside) : inside
        case let .move(plane, startPoint, startOffsets, axis):
            apply(to: point, plane: plane, startPoint: startPoint, startOffsets: startOffsets, axis: axis, projector: projector)
            events.moved(startOffsets.keys.sorted().map { PoleMove(index: $0, offset: offsets[$0] ?? .zero) }, .ended)
        }
    }

    private func apply(to point: ScreenPoint, plane: Plane, startPoint: Vector2, startOffsets: [PoleIndex: Vector3], axis: Vector3?,
                       projector: ViewportProjector) {
        guard let now = projector.planePoint(under: point, on: plane) else { return }
        var delta = plane.xAxis * (now.x - startPoint.x) + plane.yAxis * (now.y - startPoint.y)
        if let axis { delta = axis * delta.dot(axis) }
        for (index, start) in startOffsets { offsets[index] = start + delta }
    }
}

import CreatorGeometry
import CreatorKernel
import Foundation

/// Pointer input, in viewport points (y down), from `ViewportView`'s stopgap gestures (spec §9).
extension ViewportModel {
    var isPointerDown: Bool { drag != nil }

    /// A press. What the drag will do is decided here:
    /// - on the view cube, it orbits (and a click selects a region)
    /// - on a handle's knob, it edits the handle
    /// - otherwise it depends on the modifiers (`ViewportInputMap`)
    public func pointerDown(at point: ScreenPoint, modifiers: ViewportModifiers) {
        stopAnimation()
        var mode = ViewportInputMap.dragMode(for: modifiers)
        var pivot: Vector3?
        var handleStart = 0.0
        if cubeLayout.contains(point) {
            mode = .cube
        } else if let handle = HandleMath.hit(handles, at: point, pose: pose, size: viewSize) {
            mode = .handle(handle.id)
            handleStart = handle.value
        } else if mode == .orbit {
            pivot = pivotPoint(under: point)
        }
        drag = DragState(mode: mode, start: point, last: point, startPose: pose, pivot: pivot,
                         handleStartValue: handleStart)
    }

    public func pointerDragged(to point: ScreenPoint) {
        guard var state = drag else { return }
        let dx = point.x - state.last.x
        let dy = point.y - state.last.y
        switch state.mode {
        case .orbit:
            apply(CameraNavigation.orbit(pose, dx: dx, dy: dy, pivot: state.pivot))
        case .cube:
            apply(CameraNavigation.orbit(pose, dx: dx, dy: dy, pivot: nil))
        case .pan:
            apply(CameraNavigation.pan(pose, dx: dx, dy: dy, size: viewSize))
        case .zoom:
            apply(CameraNavigation.zoom(pose, factor: exp(-dy * ViewportInputMap.zoomPerPoint), toward: state.start,
                                        size: viewSize))
        case .handle(let id):
            updateHandle(id, state, to: point, phase: .changed)
        }
        state.last = point
        drag = state
    }

    /// A release. A press that moved less than `clickSlop` is a click. It puts back any tiny orbit, then picks a
    /// cube region or reports the face or edge under the pointer. Either way the hover pick is redone where the
    /// pointer now is, because the camera may have moved under it.
    public func pointerUp(at point: ScreenPoint) {
        guard let state = drag else { return }
        drag = nil
        defer {
            // The release point is where the pointer is now. Released outside the view, it's not over it at all.
            let inside = !viewSize.isEmpty && (0...viewSize.width).contains(point.x)
                && (0...viewSize.height).contains(point.y)
            lastHoverPoint = inside ? point : nil
            refreshHover()
        }
        let isClick = (point - state.start).length < ViewportInputMap.clickSlop
        switch state.mode {
        case .cube where isClick:
            apply(state.startPose)
            if let region = cubeLayout.region(at: point, pose: pose) { perform(.view(region)) }
        case .orbit where isClick:
            apply(state.startPose)
            events.clicked(pick?(point))
        case .handle(let id):
            updateHandle(id, state, to: point, phase: .ended)
        default:
            break
        }
    }

    /// The pointer moved over the viewport (`nil` when it left). Over the cube, its region is hit-tested on the CPU.
    /// Elsewhere the ID pass is asked what's under the pointer. Nothing is picked during a drag.
    public func pointerHovered(at point: ScreenPoint?) {
        lastHoverPoint = point
        guard drag == nil else { return }
        var newHovered: PickTarget?
        var newCubeRegion: ViewCubeRegion?
        if let point {
            if cubeLayout.contains(point) {
                newCubeRegion = cubeLayout.region(at: point, pose: currentPose())
            } else {
                newHovered = pick?(point)
            }
        }
        if hovered != newHovered { hovered = newHovered }
        if hoveredCubeRegion != newCubeRegion { hoveredCubeRegion = newCubeRegion }
    }

    /// The model point under `point`, else the bounds centre (spec §6.3).
    func pivotPoint(under point: ScreenPoint) -> Vector3? {
        guard !viewSize.isEmpty, point.x.isFinite, point.y.isFinite else { return sceneBounds?.center }
        let ray = CameraMath.ray(through: point, pose, size: viewSize)
        let meshes = items.enumerated().compactMap { index, item in
            cache.mesh(for: item.solid).map { (solidIndex: index, mesh: $0.mesh) }
        }
        return MeshRaycast.nearest(ray, in: meshes)?.point ?? sceneBounds?.center
    }

    func updateHandle(_ id: String, _ state: DragState, to point: ScreenPoint, phase: HandleDragPhase) {
        guard let index = handles.firstIndex(where: { $0.id == id }) else { return }
        let value = HandleMath.value(for: handles[index], startValue: state.handleStartValue, from: state.start,
                                     to: point, pose: pose, size: viewSize)
        if handles[index].value != value { handles[index].value = value }
        events.handleChanged(id, value, phase)
    }
}

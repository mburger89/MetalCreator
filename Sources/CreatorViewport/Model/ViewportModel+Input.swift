import CreatorGeometry
import CreatorKernel
import Foundation

/// Pointer input, in viewport points (y down), from `ViewportView`'s MetalUI gestures (spec §9).
extension ViewportModel {
    var isPointerDown: Bool { drag != nil }

    /// A drag's value from MetalUI: the first one begins the drag at `start` (`pointerDown`), and every one moves it
    /// to `point`. A right or middle drag while another drag is under way is ignored (`beginDragIfNeeded`).
    public func dragChanged(from start: ScreenPoint, to point: ScreenPoint, modifiers: ViewportModifiers,
                            button: ViewportPointerButton) {
        beginDragIfNeeded(from: start, modifiers: modifiers, button: button)
        guard drag?.button == button else { return }
        pointerDragged(to: point)
    }

    /// A drag's last value from MetalUI, at its release. A drag MetalUI ends without a change first begins here.
    public func dragEnded(from start: ScreenPoint, at point: ScreenPoint, modifiers: ViewportModifiers,
                          button: ViewportPointerButton) {
        beginDragIfNeeded(from: start, modifiers: modifiers, button: button)
        guard drag?.button == button else { return }
        pointerUp(at: point)
    }

    /// Begins the drag a value belongs to. The drag under way ends first, where it was, when its release must have
    /// been lost (MetalUI drops such an arena without a word, its `CI-AB`; docs/metalui-gaps.md VI-a):
    /// - a value of the same button from another press;
    /// - a primary value while another button's drag is under way: MetalUI forms the primary arena on every primary
    ///   press, apart from the button arena (`CI-F` item 3), so the primary button always gets its drag.
    /// A right or middle value while another drag is under way is ignored, as MetalUI ignores that press (`CI-AA`
    /// item 4).
    private func beginDragIfNeeded(from start: ScreenPoint, modifiers: ViewportModifiers, button: ViewportPointerButton) {
        if let state = drag {
            let lostItsRelease = state.button == button ? state.start != start : button == .primary
            if lostItsRelease { pointerUp(at: state.last) }
        }
        if drag == nil { pointerDown(at: start, modifiers: modifiers, button: button) }
    }

    /// A press. What the drag will do is decided here:
    /// - with the primary button: on the view cube, it orbits (and a click selects a region); on a handle's knob,
    ///   it edits the handle; otherwise it depends on the modifiers (`ViewportInputMap`)
    /// - with the right button it orbits (the cube's way on the cube), and with the middle button it pans
    public func pointerDown(at point: ScreenPoint, modifiers: ViewportModifiers, button: ViewportPointerButton = .primary) {
        events.pressed()
        stopAnimation()
        var mode = ViewportInputMap.dragMode(for: modifiers, button: button)
        var pivot: Vector3?
        var handleStart = 0.0
        if button != .middle, cubeLayout.contains(point) {
            mode = .cube
        } else if button == .primary, let handle = HandleMath.hit(handles, at: point, pose: pose, size: viewSize) {
            mode = .handle(handle.id)
            handleStart = handle.value
        } else if mode == .orbit {
            pivot = pivotPoint(under: point)
        }
        drag = DragState(mode: mode, button: button, start: point, last: point, startPose: pose, pivot: pivot,
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
            apply(CameraNavigation.orbit(pose, dx: dx, dy: dy, pivot: modelAreaPivot(pose)))
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
        // A drag that moved the camera settles it here. A click put it back, and a cube click animates
        // (its end reports).
        if !isAnimating, pose != state.startPose { events.cameraSettled(pose) }
    }

    /// The pointer moved over the viewport (`nil` when it left). Over the cube, its region is hit-tested on the CPU.
    /// Elsewhere the ID pass is asked what's under the pointer. Nothing is picked during a drag, or while the camera
    /// animates (the end of the animation picks once, `refreshHover()`).
    public func pointerHovered(at point: ScreenPoint?) {
        lastHoverPoint = point
        guard drag == nil, animation == nil else { return }
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

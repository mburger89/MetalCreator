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
    /// - with the primary button: on the view cube, it orbits (a click goes to `click(at:)`); on a handle's knob,
    ///   it edits the handle; with no modifier, a `tool` may take it; otherwise it depends on the modifiers
    ///   (`ViewportInputMap`)
    /// - with the right button it orbits (the cube's way on the cube), and with the middle button it pans
    /// - with planar navigation (`ViewportNavigation.planar`) there is no cube, and every drag that would orbit pans
    public func pointerDown(at point: ScreenPoint, modifiers: ViewportModifiers, button: ViewportPointerButton = .primary) {
        events.pressed()
        stopAnimation()
        var mode = ViewportInputMap.dragMode(for: modifiers, button: button)
        var pivot: Vector3?
        var handleStart = 0.0
        if button != .middle, showsViewCube, cubeLayout.contains(point) {
            mode = .cube
        } else if button == .primary, let handle = HandleMath.hit(handles, at: point, pose: pose, size: viewSize) {
            mode = .handle(handle.id)
            handleStart = handle.value
        } else if button == .primary, mode == .orbit, toolTakesDrag(at: point, modifiers: modifiers) {
            mode = .tool
        } else if mode == .orbit, isPlanar {
            mode = .pan
        } else if mode == .orbit {
            pivot = pivotPoint(under: point)
        }
        drag = DragState(mode: mode, button: button, start: point, last: point, startPose: pose, pivot: pivot,
                         handleStartValue: handleStart, modifiers: modifiers)
        if activeDragMode != mode { activeDragMode = mode }
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
            refreshToolPointer(at: point)
        case .zoom:
            apply(CameraNavigation.zoom(pose, factor: exp(-dy * ViewportInputMap.zoomPerPoint), toward: state.start,
                                        size: viewSize))
            refreshToolPointer(at: point)
        case .handle(let id):
            updateHandle(id, state, to: point, phase: .changed)
        case .tool:
            tool?.dragMoved(to: point, modifiers: state.modifiers, projector: projector)
        }
        state.last = point
        drag = state
    }

    /// A release that ends a drag. A drag never clicks, even one that comes back to where it began: clicks are
    /// `click(at:)`'s. The hover pick is redone where the pointer now is, because the camera may have moved under it.
    public func pointerUp(at point: ScreenPoint) {
        guard let state = drag else { return }
        drag = nil
        activeDragMode = nil
        if case .handle(let id) = state.mode { updateHandle(id, state, to: point, phase: .ended) }
        if state.mode == .tool { tool?.dragEnded(at: point, modifiers: state.modifiers, projector: projector) }
        // A drag that moved the camera settles it here.
        if !isAnimating, pose != state.startPose { events.cameraSettled(pose) }
        pointerReleased(at: point)
    }

    /// A click: a primary press released within MetalUI's tap slop (`SpatialTapGesture`, its location the
    /// release). On the view cube it looks at the region under the pointer; on a handle's knob it does nothing;
    /// elsewhere the `tool` may claim it, and otherwise the face or edge under the pointer (or `nil` for empty space)
    /// is offered to the tool (`clickedModel`) and, unclaimed, reported. `modifiers` are the click's (MetalUI's tap
    /// reports none yet: docs/metalui-gaps.md S5-a).
    ///
    /// A drag still under way ends first, where it was: a click is a primary press and release, so a primary drag
    /// under way lost its release, and the primary button wins over another (`beginDragIfNeeded`).
    public func click(at point: ScreenPoint, modifiers: ViewportModifiers = []) {
        if let state = drag { pointerUp(at: state.last) }
        events.pressed()
        stopAnimation()
        if showsViewCube, cubeLayout.contains(point) {
            if let region = cubeLayout.region(at: point, pose: pose) { perform(.view(region)) }
        } else if HandleMath.hit(handles, at: point, pose: pose, size: viewSize) == nil,
                  tool?.clicked(at: point, modifiers: modifiers, projector: projector) != true {
            let target = pick?(point)
            if tool?.clickedModel(target, at: point, modifiers: modifiers, projector: projector) != true {
                events.clicked(target)
            }
        }
        pointerReleased(at: point)
    }

    /// The pointer is at the release point now. Released outside the view, it's not over it at all.
    private func pointerReleased(at point: ScreenPoint) {
        let inside = !viewSize.isEmpty && (0...viewSize.width).contains(point.x) && (0...viewSize.height).contains(point.y)
        lastHoverPoint = inside ? point : nil
        refreshHover()
    }

    /// The pointer moved over the viewport (`nil` when it left). Over the cube, its region is hit-tested on the CPU.
    /// Elsewhere the ID pass is asked what's under the pointer. Nothing is picked during a drag, or while the camera
    /// animates (the end of the animation picks once, `refreshHover()`).
    public func pointerHovered(at point: ScreenPoint?) {
        lastHoverPoint = point
        if drag == nil { tool?.pointerMoved(to: point, projector: projector) }
        guard drag == nil, animation == nil else { return }
        var newHovered: PickTarget?
        var newCubeRegion: ViewCubeRegion?
        if let point {
            if showsViewCube, cubeLayout.contains(point) {
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
            item.isGuide ? nil : cache.mesh(for: item.solid).map { (solidIndex: index, mesh: $0.mesh) }
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

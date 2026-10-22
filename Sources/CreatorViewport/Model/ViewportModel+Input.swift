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

    /// A drag MetalUI dropped without an end (a press that replaced it, a release it never saw: its `CI-AB`, `IF-E` and,
    /// for a primary press that finds the arena still pressing, `GC-C` of C26) tells its owner: `onCancelled`
    /// (docs/metalui-gaps.md VI-a, VI-b). The drag of `button` under way ends where it was, as a release there would, so its
    /// mode, closed hand and settling don't outlive it. The edit is kept, as one undo step (a sketch tool's drag is
    /// committed, a handle's edit ends): consistent with Esc on a move and with a release, and it needs no revert path (user
    /// decision U4). Another button's drag, and a cancel with no drag under way, change nothing.
    public func dragCancelled(button: ViewportPointerButton) {
        guard let state = drag, state.button == button else { return }
        pointerUp(at: state.last)
    }

    /// Begins the drag a value belongs to. A primary value that arrives while another button's drag is under way ends that
    /// drag first, where it was: MetalUI forms the primary arena on every primary press, apart from the button arena
    /// (`CI-F` item 3), so the primary button always gets its drag. A right or middle value while another drag is under way
    /// is ignored, as MetalUI ignores that press (`CI-AA` item 4).
    ///
    /// A primary drag whose release was lost never reaches here: the next primary press cancels its arena first
    /// (`dragCancelled(button:)`, MetalUI C26: gap VI-b), so a primary drag under way means the same press is still going.
    private func beginDragIfNeeded(from start: ScreenPoint, modifiers: ViewportModifiers, button: ViewportPointerButton) {
        if let state = drag, button == .primary, state.button != .primary {
            pointerUp(at: state.last)
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
        if button != .middle, cubeCatches(point) {
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
    /// is offered to the tool (`clickedModel`) and, unclaimed, reported. `modifiers` are the click's own, held at its
    /// press (MetalUI's `SpatialTapGesture.Value.modifiers`, C16: docs/metalui-gaps.md GI-a).
    ///
    /// A right or middle drag still under way ends first, where it was: the primary button wins over another, as it does for
    /// a drag value (`beginDragIfNeeded`). A primary drag cannot be under way: one whose release was lost has been
    /// cancelled by this press (`dragCancelled(button:)`, MetalUI C26: gap VI-b).
    public func click(at point: ScreenPoint, modifiers: ViewportModifiers = []) {
        if let state = drag, state.button != .primary { pointerUp(at: state.last) }
        events.pressed()
        stopAnimation()
        if cubeCatches(point) {
            if let region = cubeLayout.region(at: point, pose: pose) { perform(.view(region)) }
        } else if HandleMath.hit(handles, at: point, pose: pose, size: viewSize) == nil,
                  tool?.clicked(at: point, modifiers: modifiers, projector: projector) != true {
            if isPickPending?() == true, let pickWhenReady {
                // The ID buffer for this view is still on its way: the click is delivered when it lands, not as a click on empty space.
                // It is the click of the press: the tool and the projector are those of the press, not of whatever the tool or an
                // animating camera has become by the time the buffer lands.
                let pressTool = tool
                let pressProjector = projector
                Task { [self] in
                    let target = await pickWhenReady(point)
                    deliverClick(on: target, at: point, modifiers: modifiers, tool: pressTool, projector: pressProjector)
                }
            } else {
                deliverClick(on: pick?(point), at: point, modifiers: modifiers, tool: tool, projector: projector)
            }
        }
        pointerReleased(at: point)
    }

    /// Offers a click on `target` (the face or edge under it, or `nil` for empty space) to the tool and, unclaimed, reports it.
    private func deliverClick(on target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers,
                              tool: (any ViewportTool)?, projector: ViewportProjector) {
        if tool?.clickedModel(target, at: point, modifiers: modifiers, projector: projector) != true {
            events.clicked(target)
        }
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
        if drag == nil { tool?.pointerMoved(to: point, modifiers: heldModifiers, projector: projector) }
        guard drag == nil, animation == nil else { return }
        var newHovered: PickTarget?
        var newCubeRegion: ViewCubeRegion?
        if let point {
            if cubeCatches(point) {
                newCubeRegion = cubeLayout.region(at: point, pose: currentPose())
            } else if isPickPending?() == true {
                newHovered = hovered   // the ID buffer for this view is on its way: keep the face until it lands (`onPickReady`)
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

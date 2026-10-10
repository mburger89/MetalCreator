import CreatorGeometry
import Foundation

extension ViewportModel {
    /// A scroll over the viewport (spec §6.3: zoom goes towards the cursor): `deltaY` points of scroll at `point`.
    /// Scrolling by a positive `deltaY` zooms in. Nothing settles per event (spec §7.3): a trackpad scroll settles
    /// the camera once, when it ends, and a run of wheel steps once the wheel has been still for
    /// `ViewportInputMap.wheelSettleDelay`; momentum is ignored. Returns `true`: the viewport claims every scroll over
    /// it, so none reaches the window's other input.
    @discardableResult
    public func scrolled(by deltaY: Double, at point: ScreenPoint, phase: ViewportScrollPhase) -> Bool {
        let factor = exp(deltaY * ViewportInputMap.scrollZoomPerPoint)
        switch phase {
        case .step:
            zoomScrolling(by: factor, toward: point)
            settleWhenTheWheelStops()
        case .moving:
            zoomScrolling(by: factor, toward: point)
        case .ended:
            scrollEnded()
        case .momentum:
            break
        }
        return true
    }

    /// Returns once the most recent run of wheel steps has settled.
    public func waitForScroll() async {
        while let task = wheelSettleTask {
            await task.value
            if wheelSettleTask == task { return }
        }
    }

    /// One scroll event's zoom, without settling. Every event stops an animation (one started mid-scroll by F, an arrow
    /// or the cube, which would otherwise finish over the zoom); the scroll's first event keeps the camera it began with.
    private func zoomScrolling(by factor: Double, toward point: ScreenPoint) {
        stopAnimation()
        if scrollStartPose == nil { scrollStartPose = pose }
        apply(CameraNavigation.zoom(pose, factor: factor, toward: point, size: viewSize))
        refreshToolPointer(at: point)
    }

    /// Ends the run of wheel steps once the wheel has been still for `wheelSettleDelay`: each step restarts the wait.
    private func settleWhenTheWheelStops() {
        wheelSettleTask?.cancel()
        let clock = clock
        wheelSettleTask = Task { [weak self] in
            await clock.sleep(for: ViewportInputMap.wheelSettleDelay)
            guard !Task.isCancelled, let self else { return }
            scrollEnded()
        }
    }

    /// The scroll under way ended: the hover is re-picked and the camera settles, once.
    private func scrollEnded() {
        wheelSettleTask?.cancel()
        wheelSettleTask = nil
        guard let start = scrollStartPose else { return }
        scrollStartPose = nil
        refreshHover()
        if !isAnimating, pose != start { events.cameraSettled(pose) }
    }
}

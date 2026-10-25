import CreatorGeometry
import Foundation

extension ViewportModel {
    /// A scroll over the viewport. A wheel mouse's step (`.step`) zooms toward the cursor (spec §6.3): a positive `dy`
    /// zooms in. A trackpad's two-finger scroll (`.moving`, its momentum, and a precise device's phaseless step) pans
    /// instead, the way a drag with the same delta would (the user's decision of 2026-10-24: pinch zooms, a two-finger
    /// drag pans). `dx` and `dy` are MetalUI's scroll delta in points, with natural scrolling already applied by the
    /// system, so the model follows the fingers. Nothing settles per event (spec §7.3): a run of wheel steps settles
    /// the camera once the wheel has been still for `ViewportInputMap.wheelSettleDelay`; a trackpad gesture settles
    /// it once, when its momentum ends, or `wheelSettleDelay` after the fingers lift when no momentum follows.
    /// Returns `true`: the viewport claims every scroll over it, so none reaches the window's other input.
    @discardableResult
    public func scrolled(dx: Double = 0, dy: Double, at point: ScreenPoint, phase: ViewportScrollPhase) -> Bool {
        switch phase {
        case .step:
            zoomScrolling(by: exp(dy * ViewportInputMap.scrollZoomPerPoint), toward: point)
            settleWhenScrollingStops()
        case .preciseStep:
            panScrolling(dx: dx, dy: dy, at: point)
            settleWhenScrollingStops()
        case .moving:
            panScrolling(dx: dx, dy: dy, at: point)
            wheelSettleTask?.cancel()
            wheelSettleTask = nil
        case .momentum:
            panScrolling(dx: dx, dy: dy, at: point)
            settleWhenScrollingStops()
        case .momentumEnded:
            panScrolling(dx: dx, dy: dy, at: point)
            scrollEnded()
        case .cancelled:
            scrollEnded()
        case .ended:
            // Momentum may follow at once, and cancels this wait; if none does, the gesture is over.
            settleWhenScrollingStops()
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

    /// One trackpad scroll event's pan, without settling: the model follows the fingers, as a drag pan with the same
    /// delta does. Every event stops an animation, and the scroll's first event keeps the camera it began with.
    private func panScrolling(dx: Double, dy: Double, at point: ScreenPoint) {
        stopAnimation()
        if scrollStartPose == nil { scrollStartPose = pose }
        guard dx.isFinite, dy.isFinite else { return }
        apply(CameraNavigation.pan(pose, dx: dx, dy: dy, size: viewSize))
        refreshToolPointer(at: point)
    }

    /// Ends the scroll once nothing has arrived for `wheelSettleDelay`: each event restarts the wait.
    private func settleWhenScrollingStops() {
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

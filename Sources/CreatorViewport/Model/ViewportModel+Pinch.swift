import CreatorGeometry

extension ViewportModel {
    /// A trackpad pinch (spec §6.3, docs/metalui-gaps.md C7 item 2), from MetalUI's `MagnifyGesture`:
    /// `magnification` is cumulative from 1 since the pinch began, and `centre` is where it began (the pointer
    /// doesn't move during a pinch). The camera zooms by `magnification` from where it was when the pinch began,
    /// toward `centre`. A pinch-in to zero or below holds at `ViewportInputMap.minimumMagnification` rather than
    /// springing back; a non-finite value changes nothing. A pinch that begins somewhere else while one is under
    /// way means that one lost its end (MetalUI drops such a pinch without a word, its `CI-AB`): it ends first.
    public func pinchChanged(magnification: Double, centre: ScreenPoint) {
        guard magnification.isFinite else { return }
        if let start = pinchStart, start.centre != centre { pinchEnded() }
        if pinchStart == nil {
            stopAnimation()
            pinchStart = PinchStart(pose: pose, centre: centre)
        }
        guard let start = pinchStart else { return }
        let factor = max(magnification, ViewportInputMap.minimumMagnification)
        apply(CameraNavigation.zoom(start.pose, factor: factor, toward: centre, size: viewSize))
    }

    /// The pinch ended: the camera settles where it is, once.
    public func pinchEnded() {
        guard let start = pinchStart else { return }
        pinchStart = nil
        refreshHover()
        if !isAnimating, pose != start.pose { events.cameraSettled(pose) }
    }
}

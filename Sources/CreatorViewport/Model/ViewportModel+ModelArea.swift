extension ViewportModel {
    /// The overlays' margin from the model area's edges, in points.
    static let overlayMargin = 16.0

    /// Keeps the overlays out from under the host's floating panels (spec §6.3): the view cube at the top-left of
    /// the model area, the triad at its bottom-left and the unit and grid label at its bottom-right.
    public func setModelArea(_ insets: ViewportInsets) {
        guard insets != modelArea else { return }
        modelArea = insets
        cubeLayout.origin = ScreenPoint(insets.leading + Self.overlayMargin, insets.top + Self.overlayMargin)
        triadLayout.leading = insets.leading + Self.overlayMargin
        triadLayout.bottom = insets.bottom + Self.overlayMargin
    }
}

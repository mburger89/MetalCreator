import CreatorGeometry

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

    /// The model area's centre in view points: where framing puts the part. The view's centre when the insets
    /// can't be honoured (`ViewportInsets.usable(in:)`).
    var modelAreaCentre: ScreenPoint {
        let area = modelArea.usable(in: viewSize)
        return ScreenPoint((area.leading + viewSize.width - area.trailing) / 2,
                           (area.top + viewSize.height - area.bottom) / 2)
    }

    /// The model point `pose` shows at the model area's centre, on the plane through its target. The arrows, the
    /// cube's regions and a cube drag turn about it, so a part framed in the model area stays there. With no insets
    /// it's the target.
    func modelAreaPivot(_ pose: CameraPose) -> Vector3 {
        guard !viewSize.isEmpty else { return pose.target }
        let offset = modelAreaCentre - viewSize.center
        let scale = CameraMath.millimetresPerPoint(pose, size: viewSize)
        return pose.target + pose.right * (offset.x * scale) - pose.up * (offset.y * scale)
    }

    /// `turned` moved, not turned, so that it shows `pivot` at the model area's centre.
    func centring(_ pivot: Vector3, inTheModelAreaOf turned: CameraPose) -> CameraPose {
        guard !viewSize.isEmpty else { return turned }
        let offset = modelAreaCentre - viewSize.center
        let scale = CameraMath.millimetresPerPoint(turned, size: viewSize)
        var next = turned
        next.target = pivot - turned.right * (offset.x * scale) + turned.up * (offset.y * scale)
        return next
    }
}

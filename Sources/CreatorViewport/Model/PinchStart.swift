import CreatorGeometry

/// Where a pinch in progress began: the camera it zooms from and its centre in viewport points.
struct PinchStart {
    var pose: CameraPose
    var centre: ScreenPoint
}

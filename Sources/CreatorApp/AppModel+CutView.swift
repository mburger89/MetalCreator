extension AppModel {
    /// Switches the cut view on or off (the top bar's toggle and View ▸ Show Cut View). On, it cuts the scene by the axis plane
    /// nearest the camera's view direction; with nothing shown it stays off.
    func setCutView(_ on: Bool) {
        if on {
            cutView.turnOn(bounds: viewport.sceneBounds, toEye: viewport.pose.toEye)
        } else {
            cutView.turnOff()
        }
        refreshScene()
    }
}

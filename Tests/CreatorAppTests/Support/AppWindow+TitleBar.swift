// Test fixture file: the window buttons' band, as the platform reports it.
import MetalUI
import MetalUITesting

extension AppWindow {
    /// The window buttons' band changed (full screen began or ended, a toolbar arrived): the platform's insets are set and
    /// the window is told, as AppKit reports a change of the band with no change of size.
    func setTitleBarInsets(_ insets: Edges<Pixels>) {
        window.platformWindow.titleBarInsets = insets
        window.resize(to: Size(width: Pixels(Float(size.x)), height: Pixels(Float(size.y))))
    }

    /// The inset AppKit reports with the standard window buttons: the zoom button's right edge, and the band's height.
    static let standardButtonInsets = Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(69))
}

// Test fixture file: points and counts for the window-drag tests.
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

extension AppWindow {
    /// A window point.
    func point(_ x: Float, _ y: Float) -> Point<Pixels> {
        Point(x: Pixels(x), y: Pixels(y))
    }

    /// The middle of `element`'s frame.
    func centre(of element: TestElement) -> Point<Pixels> {
        point(element.frame.origin.x.value + element.frame.size.width.value / 2,
              element.frame.origin.y.value + element.frame.size.height.value / 2)
    }

    /// How many times MetalUI asked the platform to move the window for a 40-point press-drag to the right from `start`.
    func windowDragRequests(draggingFrom start: Point<Pixels>) -> Int {
        let before = window.windowDrags
        window.drag(from: start, to: point(start.x.value + 40, start.y.value))
        return window.windowDrags - before
    }

    /// The top bar's pressable controls (buttons, the Preview picker, the Export menu), found by their frames above the
    /// bar's lower edge, so the graph panel's and the view cube's buttons are left out.
    func topBarControls() throws -> [TestElement] {
        let bottom = Float(AppLayout.margin + AppLayout.topBarHeight)
        let roles: [AccessibilityRole] = [.button, .popUpButton, .menuButton]
        return try window.elements(where: { roles.contains($0.role) && $0.frame.origin.y.value < bottom })
    }

    /// The top bar's label: the document's name or "Sketch".
    func topBarLabel() throws -> TestElement {
        let bottom = Float(AppLayout.margin + AppLayout.topBarHeight)
        let labels = try window.elements(where: { $0.role == .staticText && $0.frame.origin.y.value < bottom })
        return try #require(labels.first)
    }
}

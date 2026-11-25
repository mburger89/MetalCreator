import CreatorGeometry
import CreatorStyle
import MetalUI
import MetalUITesting

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// A headless window over one view of the drawing editor, with the app's theme store in its environment.
@MainActor
struct DrawingWindow {
    let testApp: TestApp
    let window: TestWindow
    let themes: ThemeStore

    static func open(
        size: Size<Pixels> = Size(width: Pixels(1000), height: Pixels(700)), scaleFactor: Float = 2,
        themes: ThemeStore = ThemeStore(), content: @escaping @MainActor () -> some ElementGroup
    ) async throws -> DrawingWindow {
        let testApp = try TestApp(textSystem: { testTextSystem() })
        let window = try testApp.openWindow(title: "Drawing", size: size, scaleFactor: scaleFactor) {
            ZStack(alignment: .topLeading) { content() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(themes)
        }
        try await window.runUntilIdle()
        return DrawingWindow(testApp: testApp, window: window, themes: themes)
    }

    func redraw() {
        window.window.setNeedsRedraw()
        window.tick()
    }

    /// Windows points of a canvas point, when the canvas fills the window from its top left.
    static func point(_ vector: Vector2) -> Point<Pixels> { Point(x: Pixels(Float(vector.x)), y: Pixels(Float(vector.y))) }
}

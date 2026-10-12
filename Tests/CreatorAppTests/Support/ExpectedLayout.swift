// Test fixture file: where `AppLayout`'s numbers say the graph panel should be.
import CreatorEditor
import CreatorGeometry
import CreatorGraph
@testable import CreatorApp
@testable import CreatorViewport

/// The frame `PanelArea` gives the graph dock in a `window`-sized window, worked out from `AppLayout`'s numbers. The
/// app does not use it: the panel measures itself (`EditorModel.panelPlacement`). The window tests pin the measured
/// frame against it, and the tests that draw one cold frame with `renderFrame` (which runs no `onGeometryChange`)
/// place the app with it.
@MainActor
enum ExpectedLayout {
    /// The docked panel's frame in window points; `nil` while it is hidden.
    static func graphPanelFrame(dock: DockSide, panelWidth: Double, panelHeight: Double, window: Vector2) -> CanvasRect? {
        let margin = AppLayout.margin
        let top = margin + AppLayout.topBarHeight + margin
        switch dock {
        case .left: return CanvasRect(origin: Vector2(margin, top), size: Vector2(panelWidth, max(0, window.y - top - margin)))
        case .bottom:
            return CanvasRect(origin: Vector2(margin, window.y - margin - panelHeight),
                              size: Vector2(max(0, window.x - 2 * margin), panelHeight))
        case .hidden: return nil
        }
    }

    /// The same for `app`'s dock and panel sizes.
    static func graphPanelFrame(of app: AppModel, window: Vector2) -> CanvasRect? {
        graphPanelFrame(dock: app.editor.dock, panelWidth: app.panelWidth, panelHeight: app.panelHeight, window: window)
    }

    /// Tells `app` the window's size and where its panel is, as the first layout of a real window would: for a test that
    /// draws one cold frame with `renderFrame`, which never runs `onGeometryChange`.
    static func place(_ app: AppModel, window: Vector2) {
        app.viewport.recordViewSize(ViewportSize(width: window.x, height: window.y))
        app.editor.panelPlacement = graphPanelFrame(of: app, window: window).map { PanelPlacement(window: window, panel: $0) }
    }
}

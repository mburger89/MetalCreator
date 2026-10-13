// Test fixture file: places in the app window where nothing takes a press.
import Testing
import CreatorGeometry
import MetalUI

/// A place in `AppWindow`'s default layout (graph panel docked at the bottom, a comment selected or not) where a press
/// lands on no control: the human check CT-11's three spots. Each is a window point.
enum InertSpot: CaseIterable, CustomTestStringConvertible {
    /// The graph panel's glass padding, a few points inside its corner.
    case panelGlass
    /// The gap in the graph panel's header between the breadcrumbs and the Add button.
    case headerGap
    /// An empty area of the inspector: to the right of its first section title ("NOTE", "FRAME"), above the field.
    case inspectorEmptyArea

    var testDescription: String {
        switch self {
        case .panelGlass: "panel glass"
        case .headerGap: "header gap"
        case .inspectorEmptyArea: "inspector empty area"
        }
    }

    /// The spot's window point. The panel's frame is the one the panel measured.
    @MainActor func point(in app: AppWindow) throws -> Point<Pixels> {
        switch self {
        case .panelGlass:
            let panel = try #require(app.model.panelPlacement).panel
            return app.windowPoint(panel.origin + Vector2(4, 4))
        case .headerGap:
            let panel = try #require(app.model.panelPlacement).panel
            return app.windowPoint(panel.origin + Vector2(panel.size.x / 2, 24))
        case .inspectorEmptyArea:
            return app.windowPoint(Vector2(app.size.x - 70, 84))
        }
    }
}

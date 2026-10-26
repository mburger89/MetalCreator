import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The graph panel's header buttons in the app's real window: every label is drawn in full, not cut to "Bott…",
/// at the panel's default width and when the panel is dragged wider. A button narrower than it is with room to spare
/// is a label the layout truncated.
@MainActor
struct ToolbarLabelsWindowTests {
    static let labels = ["Add", "Library", "−", "+", "Left", "Bottom", "Hide"]

    func widths(_ app: AppWindow) throws -> [String: Double] {
        let buttons = try app.window.elements { $0.role == .button && Self.labels.contains($0.label ?? "") && $0.frame.origin.y < 120 && $0.frame.origin.x < 900 }
        return Dictionary(buttons.map { ($0.label ?? "", Double($0.frame.size.width.value)) }, uniquingKeysWith: max)
    }

    @Test func everyHeaderLabelIsShownInFullAtTheDefaultPanelWidth() async throws {
        let app = try await AppWindow.open(dock: .left)
        #expect(app.model.panelWidth == AppLayout.defaultPanelWidth)
        let actual = try widths(app)
        app.model.panelWidth = AppLayout.panelWidths.upperBound
        try await app.window.runUntilIdle()
        let ideal = try widths(app)
        #expect(actual.count == Self.labels.count && ideal.count == Self.labels.count)
        for label in Self.labels {
            #expect(actual[label] == ideal[label], "“\(label)” is \(actual[label] ?? 0) wide, its ideal is \(ideal[label] ?? 0)")
        }
    }
}

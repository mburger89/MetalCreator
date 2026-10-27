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
        let buttons = try app.window.elements {
            $0.role == .button && Self.labels.contains($0.label ?? "") && $0.frame.origin.y < 120 && $0.frame.origin.x < 900
        }
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
            // Within a pixel: MetalUI rounds each edge, so a button's width is `round(x + w) - round(x)`.
            #expect(abs((actual[label] ?? 0) - (ideal[label] ?? 0)) <= 1,
                    "“\(label)” is \(actual[label] ?? 0) wide, its ideal is \(ideal[label] ?? 0)")
        }
    }

    /// What a wide font does to the default width (DejaVu Sans on Linux): the row is short of room by a few points. The
    /// panel is made that narrow instead, since the macOS font is narrower. The breadcrumbs give way, not a button.
    @Test func narrowHeaderTruncatesTheBreadcrumbsBeforeAnyButton() async throws {
        let app = try await AppWindow.open(dock: .left)
        app.model.panelWidth = AppLayout.panelWidths.upperBound
        try await app.window.runUntilIdle()
        let ideal = try widths(app)
        // The buttons and their spacing just fit in the row (390 points), the path does not.
        app.model.panelWidth = 410
        try await app.window.runUntilIdle()
        let actual = try widths(app)
        #expect(actual.count == Self.labels.count && ideal.count == Self.labels.count)
        for label in Self.labels {
            #expect(abs((actual[label] ?? 0) - (ideal[label] ?? 0)) <= 1,
                    "“\(label)” is \(actual[label] ?? 0) wide, its ideal is \(ideal[label] ?? 0)")
        }
    }
}

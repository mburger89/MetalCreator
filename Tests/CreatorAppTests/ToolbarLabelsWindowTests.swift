import CreatorEditor
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The graph panel's header icons in the app's real window: every control keeps its size at the panel's default width
/// and when the panel is dragged wider, and a narrow row truncates the breadcrumbs, never a control.
@MainActor
struct ToolbarLabelsWindowTests {
    static let labels = [HeaderText.addName, HeaderText.libraryName, HeaderText.zoomOutName, HeaderText.zoomInName,
                         HeaderText.dockLeftName, HeaderText.dockBottomName, HeaderText.hideName,
    ]

    func frames(_ app: AppWindow) throws -> [String: (minX: Double, maxX: Double)] {
        let found = try app.window.elements {
            Self.labels.contains($0.label ?? "") && $0.frame.origin.y < 120 && $0.frame.origin.x < 900
        }
        let pairs = found.map { element in
            let left = Double(element.frame.origin.x.value)
            return (element.label ?? "", (minX: left, maxX: left + Double(element.frame.size.width.value)))
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    func span(_ frames: [String: (minX: Double, maxX: Double)]) -> Double {
        (frames.values.map(\.maxX).max() ?? 0) - (frames.values.map(\.minX).min() ?? 0)
    }

    @Test func everyHeaderControlIsFoundByItsAccessibilityLabel() async throws {
        let app = try await AppWindow.open(dock: .left)
        let found = try frames(app)
        #expect(Set(found.keys) == Set(Self.labels), "found \(found.keys.sorted())")
    }

    @Test func theHeaderRowIsTheSameAtTheDefaultPanelWidthAndWider() async throws {
        let app = try await AppWindow.open(dock: .left)
        let actual = span(try frames(app))
        app.model.panelWidth = AppLayout.panelWidths.upperBound
        try await app.window.runUntilIdle()
        let ideal = span(try frames(app))
        #expect(abs(actual - ideal) <= 2, "the row is \(actual) wide, its ideal is \(ideal)")
    }

    /// A panel just wide enough for the controls and 4 points of path: the breadcrumbs give way, not a control.
    @Test func narrowHeaderTruncatesTheBreadcrumbsBeforeAnyControl() async throws {
        let app = try await AppWindow.open(dock: .left)
        app.model.panelWidth = AppLayout.panelWidths.upperBound
        try await app.window.runUntilIdle()
        let ideal = span(try frames(app))
        app.model.panelWidth = ideal + 2 * 6 + 2 * GraphPanelLayout.glassPadding + 4
        try await app.window.runUntilIdle()
        let actual = span(try frames(app))
        #expect(abs(actual - ideal) <= 2, "the row is \(actual) wide, its ideal is \(ideal)")
    }
}

import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// A click on a floating panel's glass (its title, or the padding round it) must not reach the viewport beneath: MetalUI gives
/// a painted view no hitbox, so each panel carries the opaque backdrop `GlassPanel` draws behind its content.
@MainActor
struct PanelPointerTests {
    func open() async throws -> AppWindow {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = try await AppWindow.open(builder.graph)
        app.model.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        return app
    }

    /// Clicks the title's centre and the glass padding above and left of it, with a probe as the viewport's tool, and returns
    /// how many clicks the viewport saw.
    func viewportClicks(_ app: AppWindow, title: String) async throws -> Int {
        try await app.window.runUntilIdle()
        let probe = ModifierProbeTool()
        app.model.viewport.tool = probe
        let found = try app.window.elements { $0.role == .staticText && $0.value?.lowercased() == title.lowercased() }
        let heading = try #require(found.first, "no \(title) heading in the window")
        let frame = heading.frame
        let centre = Point(x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2)
        let corner = Point(x: frame.origin.x - 4, y: frame.origin.y - 4)
        app.window.click(at: centre)
        app.window.click(at: corner)
        return probe.clicks.count
    }

    @Test func theMeasurePanelTakesItsClicks() async throws {
        let app = try await open()
        app.model.setMeasure(true)
        #expect(try await viewportClicks(app, title: "Measure") == 0)
    }

    @Test func theSectionPanelTakesItsClicks() async throws {
        let app = try await open()
        app.model.setSection(true)
        #expect(try await viewportClicks(app, title: "Section") == 0)
    }

    @Test func theZebraPanelTakesItsClicks() async throws {
        let app = try await open()
        app.model.setZebra(true)
        #expect(try await viewportClicks(app, title: "Zebra") == 0)
    }

    @Test func theInspectorAndItsParametersTakeTheirClicks() async throws {
        let app = try await open()
        #expect(try await viewportClicks(app, title: "Document Parameters") == 0)
    }
}

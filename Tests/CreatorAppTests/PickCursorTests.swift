import CreatorGeometry
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// "Pick edges in view…" shows a crosshair over the viewport (docs/metalui-gaps.md C7 item 5).
@MainActor
struct PickCursorTests {
    @Test func theViewportShowsACrosshairOnlyWhilePicking() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let rule = builder.add(EdgesByTagNode.self, at: Vector2(480, 200))
        builder.wire(box.extrude, "solid", to: rule, "solid")
        let app = await makeApp(builder.graph)
        #expect(!app.viewport.isPicking)
        app.beginPick(for: rule.id)
        await app.settle()
        #expect(app.pick != nil)
        #expect(app.viewport.isPicking)
        #expect(app.viewport.cursor == .crosshair)
        app.cancelPick()
        await app.settle()
        #expect(!app.viewport.isPicking)
        #expect(app.viewport.cursor == nil)
    }
}

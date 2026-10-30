import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The section toggle in the app's real window (section spec §5): the top bar has it, and pressing it cuts the viewport's scene.
/// How the cut looks is a human check.
@MainActor
struct SectionWindowTests {
    func open() async throws -> AppWindow {
        var builder = GraphBuilder()
        _ = builder.box()
        return try await AppWindow.open(builder.graph)
    }

    func toggles(in app: AppWindow) throws -> [TestElement] {
        try app.window.elements { $0.label == "Section" && $0.role != .staticText }
    }

    @Test func theTopBarToggleCutsTheViewportAndUncutsIt() async throws {
        let app = try await open()
        let toggle = try #require(try toggles(in: app).first)
        #expect(app.model.viewport.clip == nil)
        try app.window.click(toggle)
        try await app.window.runUntilIdle()
        #expect(app.model.document.section?.isOn == true && app.model.viewport.clip != nil)
        #expect(app.model.viewport.handles.contains { $0.id == SectionModel.handleID })
        try app.window.click(try #require(try toggles(in: app).first))
        try await app.window.runUntilIdle()
        #expect(app.model.document.section?.isOn == false && app.model.viewport.clip == nil)
    }
}

import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The cut view's toggle in the app's real window (implicit spec §5.1, §7): the top bar has it where the viewport can draw a cut, and
/// pressing it cuts the viewport's scene. How the cut looks is a human check (group IM).
@MainActor
struct CutViewWindowTests {
    func open() async throws -> AppWindow {
        var builder = GraphBuilder()
        _ = builder.box()
        return try await AppWindow.open(builder.graph)
    }

    func toggles(in app: AppWindow) throws -> [TestElement] {
        try app.window.elements { $0.label == "Cut View" && $0.role != .staticText }
    }

    #if canImport(Metal)
    @Test func theTopBarToggleCutsTheViewportAndUncutsIt() async throws {
        let app = try await open()
        #expect(CutViewModel.isAvailable)
        let toggle = try #require(try toggles(in: app).first)
        #expect(app.model.viewport.clip == nil)
        try app.window.click(toggle)
        try await app.window.runUntilIdle()
        #expect(app.model.cutView.isOn && app.model.viewport.clip != nil)
        #expect(app.model.viewport.handles.contains { $0.id == CutViewModel.handleID })
        try app.window.click(try #require(try toggles(in: app).first))
        try await app.window.runUntilIdle()
        #expect(!app.model.cutView.isOn && app.model.viewport.clip == nil)
    }
    #else
    @Test func withoutAMetalViewportThereIsNoToggle() async throws {
        let app = try await open()
        let found = try toggles(in: app)
        #expect(!CutViewModel.isAvailable && found.isEmpty)
    }
    #endif
}

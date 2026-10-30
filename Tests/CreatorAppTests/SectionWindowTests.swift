import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The section toggle and panel in the app's real window (section spec §5): the top bar has the toggle, pressing it cuts the
/// viewport's scene and shows the panel. How the cut looks is a human check.
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

    @Test func theTopBarToggleSectionsTheViewportOnEveryPlatform() async throws {
        let app = try await open()
        let toggle = try #require(try toggles(in: app).first)
        #expect(app.model.viewport.clip == nil)
        try app.window.click(toggle)
        try await app.window.runUntilIdle()
        #expect(app.model.document.section?.isOn == true && app.model.viewport.clip != nil)
        #expect(app.model.viewport.handles.contains { $0.id == SectionModel.handleID })
        #expect(try offsetFields(in: app).count == 1, "the panel is shown")
        try app.window.click(try #require(try toggles(in: app).first))
        try await app.window.runUntilIdle()
        #expect(app.model.document.section?.isOn == false && app.model.viewport.clip == nil)
        #expect(try offsetFields(in: app).isEmpty, "and gone with the section")
    }

    func offsetFields(in app: AppWindow) throws -> [TestElement] {
        try app.window.elements { $0.role == .textField && $0.label == "Offset" }
    }

    func button(_ title: String, in app: AppWindow) throws -> TestElement {
        try #require(try app.window.elements { $0.role == .button && $0.label == title }.first)
    }

    func sectionOn() async throws -> AppWindow {
        let app = try await open()
        try app.window.click(try #require(try toggles(in: app).first))
        try await app.window.runUntilIdle()
        return app
    }

    @Test func thePanelTypesAnOffsetAndFlips() async throws {
        let app = try await sectionOn()
        let field = try #require(try offsetFields(in: app).first)
        try app.window.click(field)
        app.window.typeKey("a", modifierFlags: .primary)
        app.window.typeText("7")
        app.window.typeKey(.return)
        try await app.window.runUntilIdle()
        #expect(app.model.document.section?.offset == 7)
        let typed = try #require(try offsetFields(in: app).first)
        try app.window.click(typed)
        app.window.typeKey("a", modifierFlags: .primary)
        app.window.typeText("x")
        app.window.typeKey(.return)
        try await app.window.runUntilIdle()
        #expect(app.model.document.section?.offset == 7)
        #expect(try offsetFields(in: app).first?.value == "7", "the field shows 7 again")
        let before = app.model.document.section?.isFlipped
        try app.window.click(try button("Flip", in: app))
        #expect(app.model.document.section?.isFlipped == !(before ?? false))
        try app.window.click(try button("Close", in: app))
        try await app.window.runUntilIdle()
        #expect(app.model.document.section?.isOn == false)
    }

    @Test func thePanelPicksAnOriginPlane() async throws {
        let app = try await sectionOn()
        let yz = try #require(try app.window.elements { $0.role == .radioButton && $0.label == "YZ" }.first)
        try app.window.click(yz)
        try await app.window.runUntilIdle()
        #expect(app.model.document.section?.reference == .origin(.yz))
    }
}

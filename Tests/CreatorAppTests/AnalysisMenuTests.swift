import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The top bar's Analysis menu: Section, Measure and Zebra as checkable items that can be on together.
@MainActor
struct AnalysisMenuTests {
    func open() async throws -> AppWindow {
        var builder = GraphBuilder()
        _ = builder.box()
        return try await AppWindow.open(builder.graph)
    }

    @Test func theMenuListsSectionMeasureAndZebraFollowingTheModel() async throws {
        let app = try await open()
        var items = try app.openAnalysisMenu()
        #expect(items.map(\.title) == ["Section", "Measure", "Zebra"])
        #expect(items.map(\.isOn) == [false, false, false])
        try app.window.dismissMenu()
        app.model.setSection(true)
        app.model.setZebra(true)
        try await app.window.runUntilIdle()
        items = try app.openAnalysisMenu()
        #expect(items.map(\.isOn) == [true, false, true])
        try app.window.dismissMenu()
    }

    @Test func choosingAnItemTurnsItOnAndTheOthersStay() async throws {
        let app = try await open()
        try await app.chooseAnalysis("Section")
        try await app.chooseAnalysis("Measure")
        try await app.chooseAnalysis("Zebra")
        #expect(app.model.document.section?.isOn == true)
        #expect(app.model.measure != nil)
        #expect(app.model.document.zebra?.isOn == true)
    }

    @Test func measureIsDisabledDuringAPick() async throws {
        let app = try await open()
        let solid = try #require(app.model.viewport.items.first?.solid)
        let source = try #require(app.model.producer(of: solid))
        app.model.pick = PickSession(solid: solid, source: source, rule: nil, consumer: nil, picked: [])
        try await app.window.runUntilIdle()
        let items = try app.openAnalysisMenu()
        #expect(items.first { $0.title == "Measure" }?.isEnabled == false)
        #expect(items.first { $0.title == "Zebra" }?.isEnabled == true)
        #expect(throws: TestHarnessError.self) { try app.window.chooseMenuItem("Measure") }
        try app.window.dismissMenu()
    }
}

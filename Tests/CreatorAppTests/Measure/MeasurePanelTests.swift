import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The Measure panel: its copy, its rows and their order, its numbers in the document's units, and when it shows.
@MainActor
struct MeasurePanelTests {
    func open() async throws -> AppWindow {
        var builder = GraphBuilder()
        _ = builder.box()
        return try await AppWindow.open(builder.graph)
    }

    func labels(in app: AppWindow, _ names: [String]) throws -> [String] {
        let found = try app.window.elements { $0.role != .button && (names.contains($0.label ?? "") || names.contains($0.value ?? "")) }
        return Array(Set(found.compactMap { $0.label.flatMap { names.contains($0) ? $0 : nil } ?? $0.value })).sorted()
    }

    @Test func areaTextUsesTheUnitSquared() {
        #expect(MeasurePanelText.areaText(12, units: .millimetres) == "12 mm²")
        #expect(MeasurePanelText.areaText(12.5, units: DocumentUnits(length: .millimetres, precision: 1)) == "12.5 mm²")
        let inches = DocumentUnits(length: .inches)
        let expected = DocumentUnits.number(25.4 * 25.4 / 645.16 * 1, minimum: inches.fractionDigits, maximum: inches.fractionDigits)
        #expect(MeasurePanelText.areaText(25.4 * 25.4, units: inches) == expected + " in²")
        #expect(MeasurePanelText.areaText(645.16, units: inches).hasPrefix("1."))
    }

    @Test func rowsComeInTheFixedOrder() {
        let readings = [
            MeasureReading(quantity: .position, value: 0, point: Vector3(1, 2.5, 3)),
            MeasureReading(quantity: .angle, value: 90),
            MeasureReading(quantity: .area, value: 12),
        ]
        let rows = MeasurePanelText.rows(readings: readings, distance: 7, units: .millimetres)
        #expect(rows.map(\.label) == ["Distance", "Angle", "Area", "Position"])
        #expect(rows.map(\.text) == ["7 mm", "90°", "12 mm²", "1 mm, 2.5 mm, 3 mm"])
    }

    @Test func noPickShowsThePromptAndClearIsDisabled() async throws {
        let app = try await open()
        app.model.setMeasure(true)
        try await app.window.runUntilIdle()
        let found = try labels(in: app, ["Measure", "Click a face, edge or corner."])
        #expect(found == ["Click a face, edge or corner.", "Measure"], "\(found)")
        let clear = try #require(try app.window.elements { $0.role == .button && $0.label == "Clear" }.first)
        #expect(clear.isEnabled == false)
    }

    @Test func twoFacesShowDistanceThenAngleAndDoneEndsMeasure() async throws {
        let app = try await open()
        let model = app.model
        let before = try labels(in: app, ["Distance", "Angle"])
        let solid = model.viewport.items[0].solid
        let edges = solid.topology.edges.filter { edge in
            if case .line? = edge.curve, let direction = edge.direction { return abs(abs(direction.z) - 1) < 1e-9 }
            return false
        }
        let first = try #require(edges.first)
        let second = try #require(edges.last)
        model.setMeasure(true)
        let session = try #require(model.measure)
        let projector = model.viewport.projector
        for edge in [first, second] {
            let point = projector.screenPoint(of: edge.midpoint) ?? ScreenPoint(700, 450)
            session.clickedModel(.edge(solid: 0, edge.id), at: point, modifiers: [], projector: projector)
        }
        await session.waitForDistance()
        try await app.window.runUntilIdle()
        let rows = MeasurePanelText.rows(readings: session.readings, distance: session.distance?.distance, units: model.units)
        #expect(rows.map(\.label) == ["Distance", "Angle"])
        let during = try labels(in: app, ["Distance", "Angle"])
        #expect(during == ["Angle", "Distance"], "\(before) \(during)")
        let done = try #require(try app.window.elements { $0.role == .button && $0.label == "Done" }.first)
        try app.window.click(done)
        try await app.window.runUntilIdle()
        #expect(model.measure == nil)
        #expect(try labels(in: app, ["Distance", "Angle"]) == before, "the panel is gone")
    }

    @Test func measuringShowsWhileTheDistanceIsHeld() async throws {
        let gate = FirstCallGate()
        let kernel = FakeKernel()
        await kernel.setMeasureHook { gate.enter() }
        var builder = GraphBuilder()
        _ = builder.box()
        let app = try await AppWindow.open(builder.graph, kernel: kernel)
        let model = app.model
        let solid = model.viewport.items[0].solid
        let faces = solid.topology.faces.filter { $0.kind == .plane }
        model.setMeasure(true)
        let session = try #require(model.measure)
        let projector = model.viewport.projector
        session.clickedModel(.face(solid: 0, faces[0].id), at: ScreenPoint(700, 450), modifiers: [], projector: projector)
        session.clickedModel(.face(solid: 0, faces[1].id), at: ScreenPoint(700, 450), modifiers: [], projector: projector)
        try await app.window.runUntilIdle()
        #expect(session.isMeasuring)
        #expect(try labels(in: app, ["Measuring…"]).count >= 1)
        gate.release()
        await session.waitForDistance()
        try await app.window.runUntilIdle()
        #expect(try labels(in: app, ["Measuring…"]).isEmpty)
    }

    @Test func thePanelIsAbsentWhileSketching() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(on: .xz))
        let app = try await AppWindow.open(builder.graph)
        app.model.setMeasure(true)
        try await app.window.runUntilIdle()
        let shown = try labels(in: app, ["Measure"])
        #expect(shown == ["Measure"], "\(shown)")
        app.editor.selection = [box.sketch.id]
        app.editor.press(.editSketch, on: box.sketch.id)
        try await app.window.runUntilIdle()
        #expect(try labels(in: app, ["Measure"]).isEmpty)
    }
}

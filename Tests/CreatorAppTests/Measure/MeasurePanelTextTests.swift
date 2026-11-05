import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The Measure panel's text for kept measurements, and when the panel shows with them.
@MainActor
struct MeasurePanelTextTests {
    private func entry(picks: [MeasurePick]? = [], readings: [MeasureReading] = [], distance: ShapeDistance? = nil,
                       approximate: Bool = false, resolution: Double? = nil) -> MeasureBook.Entry {
        MeasureBook.Entry(id: UUID(), picks: picks, readings: readings, distance: distance, isApproximate: approximate,
                          meshResolution: resolution, isMeasuring: false)
    }

    private let seven = ShapeDistance(distance: 7, from: Vector3(0, 0, 0), to: Vector3(7, 0, 0))

    @Test func aKeptDistanceAndAngleKeepBothRows() {
        let kept = entry(readings: [MeasureReading(quantity: .angle, value: 90)], distance: seven)
        #expect(MeasurePanelText.keptSummary(kept, units: .millimetres) == "Distance 7 mm · Angle 90°")
    }

    @Test func aKeptDistanceAndCentreDistanceKeepBothRows() {
        let kept = entry(readings: [MeasureReading(quantity: .centreDistance, value: 20)],
                         distance: ShapeDistance(distance: 15, from: Vector3(0, 0, 0), to: Vector3(15, 0, 0)))
        #expect(MeasurePanelText.keptSummary(kept, units: .millimetres) == "Distance 15 mm · Centre distance 20 mm")
    }

    @Test func aKeptRadiusAndDiameterKeepBothRows() {
        let kept = entry(readings: [MeasureReading(quantity: .radius, value: 2.5), MeasureReading(quantity: .diameter, value: 5)])
        #expect(MeasurePanelText.keptSummary(kept, units: .millimetres) == "Radius 2.5 mm · Diameter 5 mm")
    }

    @Test func severalApproximateRowsSayTheMeshOnce() {
        let kept = entry(readings: [MeasureReading(quantity: .angle, value: 90)],
                         distance: ShapeDistance(distance: 15.9, from: Vector3(0, 0, 0), to: Vector3(15.9, 0, 0)),
                         approximate: true, resolution: 0.1)
        #expect(MeasurePanelText.keptSummary(kept, units: .millimetres) == "Distance ≈ 15.9 mm · Angle ≈ 90° · mesh 0.1 mm")
    }

    @Test func aKeptRadiusSummarisesAsItsRadius() {
        let kept = entry(readings: [MeasureReading(quantity: .radius, value: 5)])
        #expect(MeasurePanelText.keptSummary(kept, units: .millimetres) == "Radius 5 mm")
    }

    @Test func everyKeptKindNamesItsNumber() {
        let words: [(MeasureQuantity, String)] = [(.radius, "Radius"), (.diameter, "Diameter"), (.length, "Length"), (.area, "Area"),
                                                  (.angle, "Angle"), (.centreDistance, "Centre distance"),
        ]
        for (quantity, word) in words {
            let kept = entry(readings: [MeasureReading(quantity: quantity, value: 2.5)])
            let panel = MeasurePanelText.rows(readings: kept.readings, distance: nil, units: .millimetres)
            #expect(panel.first?.label == word)
            #expect(MeasurePanelText.keptSummary(kept, units: .millimetres) == word + " " + panel[0].text, "\(word)")
        }
    }

    @Test func aLostOneSaysNoLongerFound() {
        let kept = entry(picks: nil, readings: [MeasureReading(quantity: .radius, value: 5)])
        #expect(MeasurePanelText.keptSummary(kept, units: .millimetres) == "No longer found")
    }

    @Test func aMeshValueIsApproximateWithItsResolution() {
        #expect(MeasurePanelText.approximate("12.3 mm", meshResolution: 0.4, units: .millimetres) == "≈ 12.3 mm · mesh 0.4 mm")
    }

    @Test func aPolylineValueIsApproximateWithoutResolution() {
        #expect(MeasurePanelText.approximate("12.3 mm", meshResolution: nil, units: .millimetres) == "≈ 12.3 mm")
    }

    @Test func anApproximateKeptValueShowsItsResolution() {
        let kept = entry(readings: [MeasureReading(quantity: .length, value: 12.3)], approximate: true, resolution: 0.4)
        #expect(MeasurePanelText.keptSummary(kept, units: .millimetres) == "Length ≈ 12.3 mm · mesh 0.4 mm")
    }

    @Test func aKeptValueUsesTheDocumentUnits() {
        let kept = entry(readings: [MeasureReading(quantity: .length, value: 25.4)])
        let inches = DocumentUnits(length: .inches)
        #expect(MeasurePanelText.keptSummary(kept, units: inches) == "Length " + inches.fieldText(25.4, quantity: .length))
        #expect(MeasurePanelText.keptSummary(kept, units: inches).hasSuffix(" in"))
    }

    @Test func anEmptyKeptEntrySaysNoValue() {
        #expect(MeasurePanelText.keptSummary(entry(), units: .millimetres) == "No value")
    }

    // MARK: - The panel

    private func keptApp() async throws -> (AppWindow, MeasureSession) {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = try await AppWindow.open(builder.graph)
        let model = app.model
        model.setMeasure(true)
        let session = try #require(model.measure)
        let solid = model.viewport.items[0].solid
        let projector = model.viewport.projector
        for edge in solid.topology.edges.prefix(2) {
            session.clickedModel(.edge(solid: 0, edge.id), at: projector.screenPoint(of: edge.midpoint) ?? ScreenPoint(700, 450),
                                 modifiers: [], projector: projector)
        }
        await session.waitForDistance()
        return (app, session)
    }

    private func buttons(_ app: AppWindow, _ label: String) throws -> [TestElement] {
        try app.window.elements { $0.role == .button && $0.label == label }
    }

    @Test func thePanelShowsWithKeptOnesAndMeasureOff() async throws {
        let (app, session) = try await keptApp()
        session.keepCurrent()
        app.model.setMeasure(false)
        try await app.window.runUntilIdle()
        #expect(app.model.measure == nil)
        #expect(!app.model.measureBook.entries.isEmpty)
        #expect(try buttons(app, MeasurePanelText.clearAll).count == 1)
        #expect(try buttons(app, "Done").isEmpty)
    }

    @Test func thePanelHidesInSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(on: .xz))
        let app = try await AppWindow.open(builder.graph)
        app.model.measureBook.add(KeptMeasurement(id: UUID(), anchors: []))
        try await app.window.runUntilIdle()
        #expect(try buttons(app, MeasurePanelText.clearAll).count == 1)
        app.editor.selection = [box.sketch.id]
        app.editor.press(.editSketch, on: box.sketch.id)
        try await app.window.runUntilIdle()
        #expect(try buttons(app, MeasurePanelText.clearAll).isEmpty)
    }

    @Test func keepIsDisabledWithNoPicksAndWhileLost() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = try await AppWindow.open(builder.graph)
        app.model.setMeasure(true)
        try await app.window.runUntilIdle()
        #expect(try #require(try buttons(app, MeasurePanelText.keep).first).isEnabled == false)
        let (second, session) = try await keptApp()
        try await second.window.runUntilIdle()
        #expect(session.isLost == false)
        #expect(try #require(try buttons(second, MeasurePanelText.keep).first).isEnabled)
    }

    @Test func theCrossRemovesOneEntry() async throws {
        let (app, session) = try await keptApp()
        session.keepCurrent()
        app.model.measureBook.add(KeptMeasurement(anchors: []))
        try await app.window.runUntilIdle()
        let before = app.model.measureBook.entries.count
        #expect(before == 2)
        let cross = try #require(try buttons(app, MeasurePanelText.remove).first)
        try app.window.click(cross)
        try await app.window.runUntilIdle()
        #expect(app.model.measureBook.entries.count == before - 1)
    }

    @Test func clearAllEmptiesTheBook() async throws {
        let (app, session) = try await keptApp()
        session.keepCurrent()
        try await app.window.runUntilIdle()
        try app.window.click(try #require(try buttons(app, MeasurePanelText.clearAll).first))
        try await app.window.runUntilIdle()
        #expect(app.model.measureBook.entries.isEmpty)
        #expect(try buttons(app, MeasurePanelText.clearAll).isEmpty)
    }
}

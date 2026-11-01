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

    @Test func aKeptDistanceSummarisesAsItsDistance() {
        let kept = entry(readings: [MeasureReading(quantity: .angle, value: 90)],
                         distance: ShapeDistance(distance: 7, from: Vector3(0, 0, 0), to: Vector3(7, 0, 0)))
        #expect(MeasurePanelText.keptSummary(kept, units: .millimetres) == "7 mm")
    }

    @Test func aKeptRadiusSummarisesAsItsRadius() {
        let kept = entry(readings: [MeasureReading(quantity: .radius, value: 5)])
        #expect(MeasurePanelText.keptSummary(kept, units: .millimetres) == "5 mm")
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

    @Test func thePanelShowsWithKeptOnesAndMeasureOff() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = try await AppWindow.open(builder.graph)
        let model = app.model
        model.setMeasure(true)
        let session = try #require(model.measure)
        let solid = model.viewport.items[0].solid
        let edge = try #require(solid.topology.edges.first)
        let projector = model.viewport.projector
        session.clickedModel(.edge(solid: 0, edge.id), at: projector.screenPoint(of: edge.midpoint) ?? ScreenPoint(700, 450),
                             modifiers: [], projector: projector)
        session.keepCurrent()
        model.setMeasure(false)
        try await app.window.runUntilIdle()
        #expect(model.measure == nil)
        #expect(!model.measureBook.entries.isEmpty)
        let shown = try app.window.elements { $0.label == "Measure" || $0.value == "Measure" }
        #expect(!shown.isEmpty)
        let clearAll = try app.window.elements { $0.role == .button && $0.label == MeasurePanelText.clearAll }
        #expect(clearAll.count == 1)
    }
}

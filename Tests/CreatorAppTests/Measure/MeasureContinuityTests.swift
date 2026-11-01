import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// Measure's Continuity row: one picked edge says how its two faces meet; it is view state like the rest of Measure.
@MainActor
struct MeasureContinuityTests {
    private func capEdge(_ fixture: MeasureAppFixture) throws -> EdgeInfo {
        try #require(fixture.solid.topology.edges.first { edge in
            guard case .line? = edge.curve, let direction = edge.direction else { return false }
            return abs(abs(direction.x) - 1) < 1e-9
        })
    }

    private func rows(_ session: MeasureSession, _ fixture: MeasureAppFixture) -> [(label: String, text: String)] {
        MeasurePanelText.valueRows(readings: session.readings, distance: session.distance?.distance,
                                   distanceFailed: session.distanceFailed, isApproximate: false, meshResolution: nil,
                                   continuity: session.continuity, continuityFailed: session.continuityFailed,
                                   units: fixture.app.units)
    }

    @Test func oneEdgeShowsItsContinuity() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        fixture.click(fixture.target(try capEdge(fixture)))
        await fixture.app.settle()
        let session = try #require(fixture.app.measure)
        let row = try #require(rows(session, fixture).first { $0.label == "Continuity" })
        #expect(row.text == "G0 · 90°")
        #expect(rows(session, fixture).contains { $0.label == "Length" })
    }

    @Test func copyForEachGrade() {
        let units = DocumentUnits()
        let g2 = EdgeContinuity(positionGap: 0, angleGap: 0, curvatureGap: 0, absoluteCurvatureGap: 0)
        let g1 = EdgeContinuity(positionGap: 0, angleGap: 0, curvatureGap: 0.384, absoluteCurvatureGap: 0.5)
        let g0 = EdgeContinuity(positionGap: 0, angleGap: 12 * Double.pi / 180, curvatureGap: 0, absoluteCurvatureGap: 0)
        #expect(MeasurePanelText.continuity(g2, units: units) == "G2")
        #expect(MeasurePanelText.continuity(g1, units: units) == "G1 · curvature jump 38 %")
        #expect(MeasurePanelText.continuity(g0, units: units) == "G0 · 12°")
    }

    @Test func aFaceOrTwoPicksShowNoContinuity() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let face = try #require(fixture.solid.topology.faces.first)
        fixture.click(.face(solid: 0, face.id))
        await fixture.app.settle()
        let session = try #require(fixture.app.measure)
        #expect(session.continuity == nil && !session.continuityFailed)
        #expect(!rows(session, fixture).contains { $0.label == "Continuity" })
        session.clear()
        fixture.click(fixture.target(fixture.verticals[0]))
        fixture.click(fixture.target(fixture.verticals[1]))
        await fixture.app.settle()
        #expect(session.picks.count == 2 && session.continuity == nil && !session.continuityFailed)
        #expect(!rows(session, fixture).contains { $0.label == "Continuity" })
    }

    @Test func anEdgeOnNoTwoFacesShowsNoRow() async throws {
        // A Fake box's vertical edges join two faces that carry no normals: the kernel says unsupported, which is no failure.
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        fixture.click(fixture.target(fixture.verticals[0]))
        await fixture.app.settle()
        let session = try #require(fixture.app.measure)
        #expect(session.continuity == nil && !session.continuityFailed && !session.isMeasuring)
        #expect(!rows(session, fixture).contains { $0.label == "Continuity" })
        #expect(rows(session, fixture).contains { $0.label == "Length" })
    }

    @Test func aFailedContinuityReadsCouldntMeasure() async throws {
        let kernel = FakeKernel()
        await kernel.setContinuityHook { throw KernelError.invalidInput("Nope.") }
        let fixture = await MeasureAppFixture.open(kernel: kernel)
        fixture.app.setMeasure(true)
        fixture.click(fixture.target(try capEdge(fixture)))
        await fixture.app.settle()
        let session = try #require(fixture.app.measure)
        #expect(session.continuityFailed)
        let all = rows(session, fixture)
        #expect(all.first { $0.label == "Continuity" }?.text == MeasurePanelText.distanceFailed)
        #expect(all.contains { $0.label == "Length" }, "the other rows stay")
    }

    @Test func aKeptEdgeAsksAgainAndFailsQuietly() async throws {
        let fixture = await MeasureAppFixture.open()
        let edge = try capEdge(fixture)
        let scene = fixture.app.measureScene()
        let anchor = try #require(MeasureResolver.anchor(for: .edge(solid: 0, edge.id), in: scene))
        fixture.app.measureBook.add(KeptMeasurement(anchors: [anchor]))
        await fixture.app.settle()
        let entry = try #require(fixture.app.measureBook.entries.first)
        #expect(entry.continuity?.grade == .g0 && !entry.continuityFailed && !entry.isMeasuring)
    }

    @Test func noUndoStepNoEdit() async throws {
        let fixture = await MeasureAppFixture.open()
        let app = fixture.app
        let title = app.undoTitle
        let before = app.document.content
        app.setMeasure(true)
        fixture.click(fixture.target(try capEdge(fixture)))
        await app.settle()
        #expect(app.document.content == before)
        #expect(app.undoTitle == title)
    }
}

import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing
@testable import CreatorApp

#if canImport(CreatorOCCT)
/// The cap over the real kernel: a section exactly on a face is a proper cross-section (the inset), and holes stay holes.
@MainActor
struct SectionCapOCCTTests {
    private func topFace(_ app: AppModel) throws -> (ref: ViewportFaceRef, pick: FacePick) {
        let solid = try #require(app.viewport.items.first).solid
        let face = try #require(solid.topology.faces.filter { $0.kind == .plane && $0.normal == .unitZ }
            .max { $0.centroid.z < $1.centroid.z })
        return (ViewportFaceRef(solidIndex: 0, face: face.id), try #require(solid.topology.facePick(for: face.id)))
    }

    private func area(of cap: ViewportSection.Cap) -> Double {
        stride(from: 0, to: cap.triangles.count, by: 3).reduce(0.0) { sum, index in
            let (a, b, c) = (cap.positions[Int(cap.triangles[index])], cap.positions[Int(cap.triangles[index + 1])],
                             cap.positions[Int(cap.triangles[index + 2])])
            return sum + (b - a).cross(c - a).length / 2
        }
    }

    @Test func sectionFromATopFaceAtOffsetZeroShowsTheFaceAsACap() async throws {
        var builder = GraphBuilder()
        _ = builder.box(distance: 10)
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        let (ref, pick) = try topFace(app)
        app.sectionFromFace(ref, pick)
        await app.settle()
        let section = try #require(app.viewport.section)
        #expect(section.caps.count == 1)
        let bounds = try #require(app.viewport.items.first).solid.bounds
        let expected = (bounds.max.x - bounds.min.x) * (bounds.max.y - bounds.min.y)
        #expect(abs(area(of: section.caps[0]) - expected) < 1e-3)
        #expect(abs(expected - 200) < 1e-3, "the default rectangle is 20 × 10")
    }

    @Test func aPlateWithAHoleShowsTheHoleInTheCap() async throws {
        var builder = GraphBuilder()
        _ = builder.sketchedBox(holedPlateSketch().sketch)
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        let (ref, pick) = try topFace(app)
        app.sectionFromFace(ref, pick)
        await app.settle()
        let cap = try #require(app.viewport.section?.caps.first)
        let full = 60.0 * 40.0
        let holes = 2 * Double.pi * 16
        #expect(abs(area(of: cap) - (full - holes)) < 1.0)
        #expect(cap.outlines.count >= 3, "the outline and both holes")
    }
}
#endif

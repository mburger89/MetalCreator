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

/// "Section from Face" in the app (section spec §3.2, §5): the plane follows a face through edits and says when it is gone.
#if canImport(CreatorOCCT)
@MainActor
struct SectionFromFaceTests {
    /// The top face of the part `node` made (the scene's order is not the graph's).
    private func topFace(_ app: AppModel, of node: Node? = nil) throws -> (ref: ViewportFaceRef, pick: FacePick) {
        let index = try #require(app.viewport.items.firstIndex { item in
            node.map { id in item.solid.topology.faces.contains { $0.tags.contains { $0.node == id.id } } } ?? true
        })
        let solid = app.viewport.items[index].solid
        let face = try #require(solid.topology.faces.filter { $0.kind == .plane && $0.normal == .unitZ }
            .max { $0.centroid.z < $1.centroid.z })
        return (ViewportFaceRef(solidIndex: index, face: face.id), try #require(solid.topology.facePick(for: face.id)))
    }

    @Test func itCutsAtTheFaceAndGoesIn() async throws {
        var builder = GraphBuilder()
        _ = builder.box(distance: 10)
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        let (ref, pick) = try topFace(app)
        app.sectionFromFace(ref, pick)
        await app.settle()
        #expect(app.document.section == SectionSettings(isOn: true, reference: .face(pick), offset: 0, isFlipped: false))
        let top = try #require(app.viewport.clip)
        #expect(top.origin.z == 10 && top.normal == .unitZ)
        app.setSectionOffset(4)
        await app.settle()
        #expect(app.viewport.clip?.origin.z == 6)
    }

    @Test func itFollowsTheFaceThroughAnEdit() async throws {
        var builder = GraphBuilder()
        let (_, extrude, _) = builder.box(distance: 10)
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        let (ref, pick) = try topFace(app)
        app.sectionFromFace(ref, pick)
        await app.settle()
        try app.document.perform(.setInput(extrude.id, "distance", .number(25)), name: UndoName.changeInput("Distance"))
        await app.settle()
        #expect(app.viewport.clip?.origin.z == 25)
    }

    @Test func aVanishedFaceKeepsTheLastPlaneAndSaysSo() async throws {
        var builder = GraphBuilder()
        let (_, extrude, output) = builder.box()
        _ = builder.box(distance: 5, at: Vector2(0, 300))
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        let (ref, pick) = try topFace(app, of: extrude)
        app.sectionFromFace(ref, pick)
        await app.settle()
        let before = try #require(app.viewport.clip)
        try app.document.perform(.removeNode(output.id), name: UndoName.delete)
        await app.settle()
        #expect(app.viewport.clip == before && app.section.note == "The section's face no longer exists.")
        let settings = try #require(app.document.section)
        var rest = GraphBuilder()
        _ = rest.box(distance: 5)
        let fresh = await makeApp(rest.graph, kernel: OCCTKernel())
        fresh.document.section = settings
        fresh.refreshScene()
        await fresh.settle()
        #expect(fresh.viewport.clip == nil && fresh.section.note == "The section's face no longer exists.")
    }

    @Test func nothingStartsWhileASketchIsOpen() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let sketch = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(Sketch(plane: .fixed(.xy)))], at: Vector2(0, 300))
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        let (ref, pick) = try topFace(app)
        app.beginSketch(for: sketch.id)
        await app.settle()
        app.sectionFromFace(ref, pick)
        await app.settle()
        #expect(app.document.section == nil)
    }
}
#endif

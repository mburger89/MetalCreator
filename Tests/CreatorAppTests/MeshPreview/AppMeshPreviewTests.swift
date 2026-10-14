import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// A mesh in the app (implicit spec §5.1, §4.3): it appears at once as the first pass, gets finer in the background, and an edit starts
/// the passes over for the new shape.
@MainActor
struct AppMeshPreviewTests {
    /// Sphere → Mesh → Output, previewed down to 0.06 mm.
    func graph(radius: Double = 6, preview: Double = 0.06) -> (graph: Graph, sphere: Node, mesh: Node, output: Node) {
        var builder = GraphBuilder()
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(radius)])
        let mesh = builder.add(MeshNode.self, ["preview resolution": .number(preview)])
        let output = builder.add(OutputNode.self)
        builder.wire(sphere, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        return (builder.graph, sphere, mesh, output)
    }

    /// How many triangles the viewport's one item has.
    func triangles(_ app: AppModel) -> Int? {
        app.viewport.items.first?.solid.displayedMesh.map { $0.indices.count / 3 }
    }

    @Test func theFirstPassIsShownAtOnceAndRefinesInTheBackground() async throws {
        let fixture = graph()
        let app = await makeApp(fixture.graph)
        #expect(app.viewport.items.count == 1 && app.viewport.items[0].solid.displayedMesh != nil)
        let coarse = try #require(triangles(app))
        #expect(app.meshRefinement.badge == .init(text: "Preview 0.094 mm", isRefining: true))
        await app.meshRefinement.waitForRefinement()
        await app.settle()
        let fine = try #require(triangles(app))
        #expect(fine > coarse, "the finer pass replaced the coarse one: \(coarse) → \(fine) triangles")
        #expect(app.meshRefinement.badge == .init(text: "Preview 0.06 mm", isRefining: false))
        #expect(app.viewport.items.count == 1)
    }

    @Test func anEditStopsThePassesForTheOldShapeAndStartsTheNewOne() async throws {
        let fixture = graph()
        let app = await makeApp(fixture.graph)
        let before = Set(app.meshRefinement.statuses.keys)
        try app.document.perform(.setInput(fixture.sphere.id, "radius", .number(5)))
        await app.settle()
        let after = Set(app.meshRefinement.statuses.keys)
        #expect(before.count == 1 && after.count == 1 && before.isDisjoint(with: after), "the old mesh is forgotten")
        await app.meshRefinement.waitForRefinement()
        await app.settle()
        #expect(app.meshRefinement.badge?.isRefining == false)
        let mesh = try #require(app.viewport.items.first?.solid.displayedMesh)
        let bounds = try #require(BoundingBox(points: mesh.positions))
        #expect(abs(bounds.max.x - 5) < 0.06, "the finest pass is the new radius")
    }

    @Test func nothingIsRefinedWithoutAMesh() async {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = await makeApp(builder.graph)
        #expect(app.meshRefinement.badge == nil && app.meshRefinement.statuses.isEmpty)
    }

    @Test func openingAnotherDocumentStopsTheRefinement() async throws {
        let fixture = graph()
        let app = await makeApp(fixture.graph)
        app.load(GraphFile(), from: nil)
        await app.settle()
        #expect(app.meshRefinement.badge == nil && app.meshRefinement.refined.isEmpty)
        #expect(app.viewport.items.isEmpty)
    }

    @Test func aMeshPreviewDoesNotDependOnTheKernel() async throws {
        let fixture = graph(preview: 1)
        let kernel = FakeKernel()
        await kernel.clearLog()
        let app = await makeApp(fixture.graph, kernel: kernel)
        #expect(app.viewport.items.count == 1)
        #expect(await !kernel.operationLog.contains("tessellate"))
    }

    @Test func theSceneSourceOfAMeshIsItsOutputSocket() async throws {
        let fixture = graph(preview: 1)
        let app = await makeApp(fixture.graph)
        let solid = try #require(app.viewport.items.first?.solid)
        #expect(app.sources[ObjectIdentifier(solid)] == Endpoint(node: fixture.output.id, socket: "mesh"))
    }
}

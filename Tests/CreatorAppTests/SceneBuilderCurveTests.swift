import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// A curve on an Output node's `curve` output is one curve item in the scene (NURBS spec): faceless, in the scene's bounds.
@MainActor
struct SceneBuilderCurveTests {
    @Test func anOutputWithACurveGivesOneCurveItem() async throws {
        let curve = try await FakeKernel().makeCurve([.line(Vector3(0, 0, 0), Vector3(0, 0, 30))],
                                                     tag: NodeTag(node: NodeID(), item: 0))
        let output = BuiltInNodes.registry.makeNode(OutputNode.typeID)
        let graph = Graph(nodes: [output.id: output])
        let items = SceneBuilder.items(of: output, outputs: ["curve": .list([.curve(curve)])], isGhost: false, graph: graph)
        #expect(items.count == 1)
        let item = try #require(items.first?.item)
        #expect(item.isCurve && !item.isGhost)
        #expect(item.solid.topology.faces.isEmpty)
        #expect(item.solid.bounds == curve.bounds)
        #expect(item.solid.displayedMesh?.edgePolylines[EdgeID(0)] == curve.polyline)
        #expect(items.first?.source == Endpoint(node: output.id, socket: "curve"))
    }
}

/// NS-1 Task 10 fix round: a curve item is made once per curve, and measure and the section's cap leave it alone.
@MainActor
struct CurveItemFixTests {
    func curveApp() async -> AppModel {
        var builder = GraphBuilder()
        let rectangle = builder.add(RectangleNode.self)
        let curves = builder.add(ProfileToCurvesNode.self)
        let output = builder.add(OutputNode.self)
        builder.wire(rectangle, "profile", to: curves, "profile")
        builder.wire(curves, "curves", to: output, "curve")
        return await makeApp(builder.graph)
    }

    @Test func aCurveKeepsItsDisplaySolidAcrossRebuilds() async throws {
        let curve = try await FakeKernel().makeCurve([.line(Vector3(0, 0, 0), Vector3(0, 0, 30))],
                                                     tag: NodeTag(node: NodeID(), item: 0))
        let output = BuiltInNodes.registry.makeNode(OutputNode.typeID)
        let graph = Graph(nodes: [output.id: output])
        let meshes = MeshScene(solids: MeshSolids())
        let outputs: [SocketName: Value] = ["curve": .list([.curve(curve)])]
        let first = SceneBuilder.items(of: output, outputs: outputs, isGhost: false, graph: graph, meshes: meshes)
        let second = SceneBuilder.items(of: output, outputs: outputs, isGhost: false, graph: graph, meshes: meshes)
        #expect(first[0].item.solid === second[0].item.solid)
        #expect(first[0].item.drawsTheSame(as: second[0].item))
    }

    @Test func aCanvasPanDoesNotReloadASceneWithACurve() async throws {
        let app = await curveApp()
        #expect(app.viewport.items.contains { $0.isCurve })
        let generation = app.viewport.sceneGeneration
        app.editor.transform = app.editor.transform.panned(by: Vector2(30, 10))
        await app.settle()
        app.refreshScene()
        await app.settle()
        #expect(app.viewport.sceneGeneration == generation)
    }

    @Test func aCurveIsNotPickableForMeasure() async throws {
        let app = await curveApp()
        let scene = app.measureScene()
        let curves = app.viewport.items.indices.filter { app.viewport.items[$0].isCurve }
        #expect(!curves.isEmpty)
        #expect(curves.allSatisfy { !scene.pickable[$0] })
        #expect(MeasureResolver.resolve(.meshPoint(Vector3(1, 2, 3)), in: scene) == nil,
                "a kept mesh point with no mesh left reads No longer found while a curve is shown")
    }

    @Test func aCurveGetsNoSectionCap() async throws {
        let curve = try await FakeKernel().makeCurve([.line(Vector3(0, 0, -5), Vector3(0, 0, 30))],
                                                     tag: NodeTag(node: NodeID(), item: 0))
        let model = SectionCapModel(kernel: FakeKernel(), tolerance: 0.05)
        model.follow(clip: ViewportClip(origin: Vector3(0, 0, 1), normal: .unitZ), items: [ViewportItem(curve: curve)])
        await model.waitForCaps()
        #expect(model.slicesStarted == 0 && model.preparesDone == 0 && model.section == nil && model.problem == nil)
    }
}

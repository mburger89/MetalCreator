import CreatorGeometry
import CreatorGraph
@testable import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// A click on the part selects the feature behind it (DIM-3 Task 12, decision 3).
@MainActor
struct FeatureClickTests {
    /// A plate (Rectangle → Extrude) with a Slot Pattern on it → Output. A Slot Pattern stands for the Hole Pattern: both place
    /// instances and declare dimensions, and FakeKernel can extrude a slot but not revolve a hole.
    struct Plate {
        var builder = GraphBuilder()
        var rectangle: Node
        var extrude: Node
        var holes: Node  // the pattern
        var output: Node

        init() {
            let (rectangle, extrude) = builder.solid()
            let grid = builder.add(GridPointsNode.self, at: Vector2(0, 200))
            let placements = builder.add(PointsToPlacementsNode.self, at: Vector2(240, 200))
            holes = builder.add(SlotPatternNode.self, at: Vector2(480, 0))
            output = builder.add(OutputNode.self, at: Vector2(720, 0))
            builder.wire(grid, "points", to: placements, "points")
            builder.wire(extrude, "solid", to: holes, "part")
            builder.wire(placements, "placements", to: holes, "placements")
            builder.wire(holes, "solid", to: output, "solid")
            self.rectangle = rectangle
            self.extrude = extrude
        }
    }

    /// Shows a solid whose faces carry exactly `faces` (id → tags) and whose edges join the given face pairs, in place of the
    /// scene (FakeKernel makes no holes).
    func show(_ app: AppModel, faces: [Set<TopoTag>], edges: [(Int, Int)] = []) async {
        let topology = Topology(
            faces: faces.enumerated().map { index, tags in
                FaceInfo(id: FaceID(index), kind: .plane, normal: nil, area: 0, centroid: .zero, tags: tags)
            },
            edges: edges.enumerated().map { index, pair in
                EdgeInfo(id: EdgeID(index), kind: .line, direction: nil, length: 1, midpoint: .zero, convexity: .convex,
                         faces: [FaceID(pair.0), FaceID(pair.1)])
            })
        let bounds = BoundingBox(min: .zero, max: Vector3(1, 1, 1))
        app.viewport.show([ViewportItem(solid: Solid(topology: topology, bounds: bounds, storage: FakeStorage()))])
        await app.viewport.waitForMeshes()
    }

    func tag(_ node: NodeID, _ role: TopoRole = .endCap, item: Int = 0) -> TopoTag { TopoTag(node: node, item: item, role: role) }

    @Test func clickingAPlatesFaceSelectsItsExtrude() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        try #require(!app.viewport.items.isEmpty)
        let top = try #require(app.viewport.items[0].solid.topology.face(FaceID(1)))
        #expect(top.tags.contains { $0.node == box.extrude.id }, "FakeKernel tags the top cap with the extrude")
        app.viewportClicked(.face(solid: 0, FaceID(1)))
        #expect(app.editor.selection == [box.extrude.id])
    }

    @Test func clickingAHoleWallSelectsTheHolePattern() async throws {
        let plate = Plate()
        let app = await makeApp(plate.builder.graph)
        try #require(app.document.results[plate.holes.id]?.dimensions.isEmpty == false,
                     "the pattern declares dimensions: \(String(describing: app.document.results[plate.holes.id]?.state))")
        let wall = tag(NodeID.instanceScoped([plate.holes.id, plate.holes.id]), .side(loop: 0, segment: 1), item: 3)
        await show(app, faces: [[tag(plate.extrude.id)], [wall]])
        app.viewportClicked(.face(solid: 0, FaceID(1)))
        #expect(app.editor.selection == [plate.holes.id])
    }

    @Test func anEdgeBetweenTwoFeaturesSelectsTheLaterOne() async throws {
        let plate = Plate()
        let app = await makeApp(plate.builder.graph)
        let wall = tag(NodeID.instanceScoped([plate.holes.id, plate.holes.id]), .side(loop: 0, segment: 1))
        await show(app, faces: [[tag(plate.extrude.id)], [wall]], edges: [(0, 1)])
        app.viewportClicked(.edge(solid: 0, EdgeID(0)))
        #expect(app.editor.selection == [plate.holes.id], "the rim of a hole is the pattern's, not the plate's")
    }

    @Test func aNodeWithoutDimensionsDefersUpstream() async throws {
        var builder = GraphBuilder()
        let first = builder.solid()
        let second = builder.solid(at: Vector2(0, 300))
        let union = builder.add(BooleanNode.self, at: Vector2(480, 0))
        let output = builder.add(OutputNode.self, at: Vector2(720, 0))
        builder.wire(first.extrude, "solid", to: union, "target")
        builder.wire(second.extrude, "solid", to: union, "tools")
        builder.wire(union, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        try #require(app.document.results[union.id]?.dimensions.isEmpty == true)
        await show(app, faces: [[tag(union.id)]])
        app.viewportClicked(.face(solid: 0, FaceID(0)))
        #expect(app.editor.selection == [min(first.extrude.id, second.extrude.id)], "the nearest declaring node, lowest ID first")
    }

    @Test func emptySpaceClearsTheSelection() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        app.viewportClicked(nil)
        #expect(app.editor.selection.isEmpty)
    }

    @Test func aTaglessFaceChangesNothing() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        await show(app, faces: [[]])
        app.editor.selection = [box.rectangle.id]
        app.viewportClicked(.face(solid: 0, FaceID(0)))
        #expect(app.editor.selection == [box.rectangle.id])
        app.viewportClicked(.face(solid: 5, FaceID(0)))
        #expect(app.editor.selection == [box.rectangle.id], "a solid that isn't shown changes nothing either")
    }

    @Test func inSelectedNodePreviewAClickSelectsNothing() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.previewMode = .selectedNode
        app.editor.selection = [box.rectangle.id]
        await app.settle()
        await show(app, faces: [[tag(box.extrude.id)]])
        app.viewportClicked(.face(solid: 0, FaceID(0)))
        #expect(app.editor.selection == [box.rectangle.id])
        app.viewportClicked(nil)
        #expect(app.editor.selection == [box.rectangle.id], "empty space doesn't clear it here either")
    }

    @Test func insideAGroupAFaceSelectsTheInnerNode() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        await app.settle()
        await show(app, faces: [[tag(NodeID.scoped([group, box.extrude.id]))]])
        app.viewportClicked(.face(solid: 0, FaceID(0)))
        #expect(app.editor.selection == [box.extrude.id])
        app.editor.exitGroup()
        await app.settle()
        await show(app, faces: [[tag(NodeID.scoped([group, box.extrude.id]))]])
        app.viewportClicked(.face(solid: 0, FaceID(0)))
        #expect(app.editor.selection == [group], "from outside the same face is the group's")
    }

    @Test func aClickWhilePickingStillPicksEdges() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let rule = builder.add(EdgesByTagNode.self, at: Vector2(480, 0))
        let chamfer = builder.add(ChamferNode.self, at: Vector2(720, 0))
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(box.extrude, "solid", to: rule, "solid")
        builder.wire(rule, "edges", to: chamfer, "edges")
        builder.wire(chamfer, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.editor.selection = [chamfer.id]
        app.beginPick(for: rule.id)
        await app.settle()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        #expect(app.pick?.picked.contains(EdgeID(1)) == true)
        #expect(app.editor.selection == [chamfer.id], "picking selects nothing")
        app.viewportClicked(nil)
        #expect(app.editor.selection == [chamfer.id])
    }

    @Test func theMostDownstreamTagWinsAndTiesTakeTheLowestID() {
        var builder = GraphBuilder()
        let (rectangle, extrude) = builder.solid()
        let other = builder.add(ExtrudeNode.self, at: Vector2(0, 300))
        let line = DimensionGeometry.linear(from: .zero, to: .unitX, direction: .unitX, side: .unitY, placement: .standoff)
        let spec = DimensionSpec(.input("distance"), line, .length, value: 1)
        let results = Dictionary(uniqueKeysWithValues: [rectangle, extrude, other].map {
            ($0.id, NodeResult(state: .ok(duration: .zero), dimensions: [spec]))
        })
        let producers = Dictionary(uniqueKeysWithValues: [rectangle, extrude, other].map { ($0.id, $0.id) })
        let graph = builder.graph
        #expect(AppModel.feature(for: [rectangle.id, extrude.id], producers: producers, graph: graph, results: results) == extrude.id)
        #expect(AppModel.feature(for: [extrude.id, other.id], producers: producers, graph: graph, results: results)
            == min(extrude.id, other.id), "unrelated candidates tie")
        #expect(AppModel.feature(for: [NodeID()], producers: producers, graph: graph, results: results) == nil)
    }
}

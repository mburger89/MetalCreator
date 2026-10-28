import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorApp
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

/// DIM-4: what a picked face or edge of the part comes from in the sketches (spec §3.5), on OCCT's real faces and tags.
@MainActor
struct ModelDimensionTraceTests {
    #if canImport(CreatorOCCT)
    /// A part evaluated on OCCT, with its graph and results as the viewport tool sees them.
    @MainActor
    struct Part {
        let app: AppModel
        let solid: Solid

        var graph: Graph { app.editor.graph }
        var results: [NodeID: NodeResult] { app.editor.levelResults }

        func items(_ target: PickTarget) -> [SketchItem] {
            ModelDimensionTrace.items(for: target, solid: solid, graph: graph, results: results)
        }

        func face(_ role: TopoRole) throws -> FaceInfo {
            try #require(solid.topology.faces.first { face in face.tags.contains { $0.role == role } })
        }

        /// The edge between the faces carrying `first` and `second`.
        func edge(_ first: TopoRole, _ second: TopoRole) throws -> EdgeInfo {
            let (a, b) = (try face(first).id, try face(second).id)
            return try #require(solid.topology.edges.first { Set($0.faces) == [a, b] })
        }
    }

    /// The part the viewport shows (the widest, when the graph makes several).
    func part(_ builder: GraphBuilder, smallest: Bool = false) async throws -> Part {
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        let parts = app.viewport.items.filter { !$0.isGhost && !$0.isGuide }.map(\.solid)
        let bySize = parts.sorted { $0.bounds.size.x < $1.bounds.size.x }
        let solid = try #require(smallest ? bySize.first : bySize.last)
        return Part(app: app, solid: solid)
    }

    /// `extrude`'s solid with `selected` previewed, so that the chain around `selected` is evaluated.
    func previewing(_ selected: Node, solidOf extrude: Node, _ builder: GraphBuilder) async throws -> Part {
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        app.editor.selection = [selected.id]
        app.previewMode = .selectedNode
        await app.settle()
        let solid = try #require(solids(app, extrude).first)
        return Part(app: app, solid: solid)
    }

    func plate() async throws -> (part: Part, plate: HoledPlate, sketch: Node) {
        var builder = GraphBuilder()
        let plate = holedPlateSketch()
        let (sketch, _) = builder.sketchedBox(plate.sketch)
        return (try await part(builder), plate, sketch)
    }

    @Test func aWallTracesToItsSketchLine() async throws {
        let (part, plate, sketch) = try await plate()
        let wall = try part.face(.side(segment: 0))
        #expect(part.items(.face(solid: 0, wall.id)) == [SketchItem(node: sketch.id, entity: plate.lines[0])])
    }

    @Test func aTopEdgeTracesToTheLineUnderIt() async throws {
        let (part, plate, sketch) = try await plate()
        let edge = try part.edge(.endCap, .side(segment: 2))
        #expect(part.items(.edge(solid: 0, edge.id)) == [SketchItem(node: sketch.id, entity: plate.lines[2])])
    }

    @Test func anUprightEdgeTracesToTheCornerPoint() async throws {
        let (part, plate, sketch) = try await plate()
        let edge = try part.edge(.side(segment: 0), .side(segment: 1))
        #expect(part.items(.edge(solid: 0, edge.id)) == [SketchItem(node: sketch.id, entity: plate.corners[1])])
    }

    @Test func aHoleRimTracesToItsCircle() async throws {
        let (part, plate, sketch) = try await plate()
        let wall = try part.face(.side(loop: 1, segment: 0))
        let rim = try #require(part.solid.topology.edges.first { edge in
            edge.kind == .circle && edge.faces.contains(wall.id)
                && edge.faces.contains { id in part.solid.topology.face(id)?.tags.contains { $0.role == .endCap } == true }
        })
        let circle = [SketchItem(node: sketch.id, entity: plate.circles[0])]
        #expect(part.items(.edge(solid: 0, rim.id)) == circle)
        #expect(part.items(.face(solid: 0, wall.id)) == circle)
    }

    @Test func aCapTracesToNothing() async throws {
        let (part, _, _) = try await plate()
        #expect(part.items(.face(solid: 0, try part.face(.endCap).id)).isEmpty)
    }

    @Test func aPartNotFromASketchTracesToNothing() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let part = try await part(builder)
        for face in part.solid.topology.faces { #expect(part.items(.face(solid: 0, face.id)).isEmpty) }
        for edge in part.solid.topology.edges { #expect(part.items(.edge(solid: 0, edge.id)).isEmpty) }
    }

    @Test func somethingBetweenTheSketchAndTheSweepBreaksTheTrace() async throws {
        var builder = GraphBuilder()
        let sketch = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangleSketch())])
        let item = builder.add(ListItemNode.self, at: Vector2(120, 0))
        let extrude = builder.add(ExtrudeNode.self, ["distance": .number(10)], at: Vector2(240, 0))
        let output = builder.add(OutputNode.self, at: Vector2(480, 0))
        builder.wire(sketch, "profiles", to: item, "tree")
        builder.wire(item, "item", to: extrude, "profile")
        builder.wire(extrude, "solid", to: output, "solid")
        let part = try await part(builder)
        #expect(part.solid.topology.faces.contains { $0.tags.contains { if case .side = $0.role { true } else { false } } })
        for face in part.solid.topology.faces { #expect(part.items(.face(solid: 0, face.id)).isEmpty) }
        for edge in part.solid.topology.edges { #expect(part.items(.edge(solid: 0, edge.id)).isEmpty) }
    }

    @Test func theItemPicksTheRegion() async throws {
        var sketch = Sketch(plane: .fixed(.xy))
        func rectangle(_ origin: Vector2, _ width: Double, _ height: Double) -> [SketchEntityID] {
            let corners = [origin, origin + Vector2(width, 0), origin + Vector2(width, height), origin + Vector2(0, height)]
                .map { sketch.addPoint($0) }
            return (0..<4).map { sketch.addLine(from: corners[$0], to: corners[($0 + 1) % 4]) }
        }
        let big = rectangle(.zero, 80, 40)
        let small = rectangle(Vector2(100, 0), 20, 20)
        var builder = GraphBuilder()
        let (node, _) = builder.sketchedBox(sketch)
        let part = try await part(builder, smallest: true)
        let smallest = try #require(part.solid.topology.faces.filter { face in
            face.tags.contains { if case .side = $0.role { true } else { false } }
        }.min { $0.area < $1.area })
        #expect(abs(smallest.area - 20 * 10) < 1e-6)
        let traced = part.items(.face(solid: 0, smallest.id))
        #expect(traced.count == 1 && traced[0].node == node.id)
        #expect(small.contains(traced[0].entity) && !big.contains(traced[0].entity))
    }

    @Test func aProjectedEdgeTracesToTheSketchHoldingItToo() async throws {
        let plate = holedPlateSketch()
        var builder = GraphBuilder()
        let (first, extrude) = builder.sketchedBox(plate.sketch)
        var drawing = Sketch(plane: .fixed(.xy))
        let projected = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .line(.zero, Vector2(1, 0))))))
        let second = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)], at: Vector2(0, 200))
        builder.wire(extrude, "solid", to: second, "references")
        // The first pass finds the right top edge (cap | the plate's right wall); the pick then goes in the second Sketch.
        let probe = try await previewing(second, solidOf: extrude, builder)
        let edge = try probe.edge(.endCap, .side(segment: 1))
        var secondNode = try #require(builder.graph.nodes[second.id])
        secondNode.inputValues[NodeSetting.projection("p1")] = .edgePicks(probe.solid.topology.picks(for: [edge.id]))
        builder.replace(secondNode)
        let part = try await previewing(second, solidOf: extrude, builder)
        let traced = part.items(.edge(solid: 0, try part.edge(.endCap, .side(segment: 1)).id))
        #expect(traced == [SketchItem(node: first.id, entity: plate.lines[1]), SketchItem(node: second.id, entity: projected)])
    }
    #endif

    @Test func sharedTakesTheFirstSketchBothHave() {
        let (a, b) = (NodeID(), NodeID())
        let a1 = SketchItem(node: a, entity: SketchEntityID(1))
        let b1 = SketchItem(node: b, entity: SketchEntityID(2))
        let b2 = SketchItem(node: b, entity: SketchEntityID(3))
        let pair = ModelDimensionTrace.shared([a1, b1], [b2])
        #expect(pair?.0 == b1 && pair?.1 == b2)
        #expect(ModelDimensionTrace.shared([a1], [b2]) == nil)
    }
}

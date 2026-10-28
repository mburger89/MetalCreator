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

/// The holed plate (60 × 40, 10 thick) with its app, the Sketch node and the Extrude.
@MainActor
struct ModelDimensionPlate {
    let app: AppModel
    let plate: HoledPlate
    let sketch: Node
    let extrude: Node

    var solid: Solid { app.viewport.items[index].solid }
    /// The viewport item of the plate: the one with circular edges.
    var index: Int { app.viewport.items.firstIndex { $0.solid.topology.edges.contains { $0.kind == .circle } } ?? 0 }

    var stored: Sketch {
        guard case .sketch(let sketch)? = app.editor.graph.nodes[sketch.id]?.inputValues[NodeSetting.sketch] else {
            Issue.record("no sketch stored")
            return Sketch(plane: .fixed(.xy))
        }
        return sketch
    }

    /// The circular edge of hole `hole` (0 or 1) at the top (`top`) or bottom.
    func rim(_ hole: Int, top: Bool = true) throws -> PickTarget {
        let topology = solid.topology
        let walls = topology.faces.filter { face in
            face.tags.contains { $0.role == .side(loop: hole + 1, segment: 0) }
        }
        let wall = try #require(walls.first)
        let rims = topology.edges.filter { $0.kind == .circle && $0.faces.contains(wall.id) }
        let edge = try #require(rims.sorted { $0.midpoint.z < $1.midpoint.z }[top ? rims.count - 1 : 0])
        return .edge(solid: index, edge.id)
    }

    func wall(_ segment: Int) throws -> PickTarget {
        let face = try #require(solid.topology.faces.first { $0.tags.contains { $0.role == .side(segment: segment) } })
        return .face(solid: index, face.id)
    }

    /// The edge where the top cap meets wall `segment`.
    func topEdge(_ segment: Int) throws -> PickTarget {
        let cap = try #require(solid.topology.faces.first { $0.tags.contains { $0.role == .endCap } }?.id)
        let side = try #require(solid.topology.faces.first { $0.tags.contains { $0.role == .side(segment: segment) } }?.id)
        let edge = try #require(solid.topology.edges.first { Set($0.faces) == [cap, side] })
        return .edge(solid: index, edge.id)
    }

    func newDimension(after before: Sketch) -> SketchDimension? {
        let added = Set(stored.dimensions.keys).subtracting(before.dimensions.keys)
        return added.count == 1 ? added.first.flatMap { stored.dimensions[$0] } : nil
    }

    func rimCentres() -> [Vector3] {
        solid.topology.edges.filter { $0.kind == .circle }.map(\.midpoint)
            .sorted { ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z) }
    }

    func centre(_ circle: SketchEntityID) throws -> SketchEntityID {
        guard case .circle(let centre, _)? = stored.entities[circle]?.kind else {
            Issue.record("not a circle")
            return circle
        }
        return centre
    }
}

extension ModelDimensionToolTests {
    func plate(_ sketch: Sketch? = nil, values: [SocketName: ConstantValue] = [:],
               extra: ((inout GraphBuilder) -> Void)? = nil) async throws -> ModelDimensionPlate {
        var builder = GraphBuilder()
        let holed = holedPlateSketch()
        let (node, extrude) = builder.sketchedBox(sketch ?? holed.sketch, values: values)
        extra?(&builder)
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        return ModelDimensionPlate(app: app, plate: holed, sketch: node, extrude: extrude)
    }

    /// The first pick's hole is deleted from the sketch (one `perform`), then the second pick is made.
    func staleApp(settling: Bool) async throws -> (part: ModelDimensionPlate, graph: Graph) {
        let part = try await plate()
        let app = part.app
        app.beginModelDimension()
        app.viewportClicked(try part.rim(0))
        try #require(app.modelDimension?.pickedCount == 1)
        var changed = part.stored
        changed.removeEntity(part.plate.circles[0])
        try app.document.perform(.setInput(part.sketch.id, NodeSetting.sketch, .sketch(changed)), at: app.editor.graphPath,
                                 name: "Edit")
        if settling { await app.settle() }
        return (part, app.document.graph)
    }
}
#endif

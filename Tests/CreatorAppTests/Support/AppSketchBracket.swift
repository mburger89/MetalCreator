// Test fixture file: DIM-4's sketched bracket, built in an app the way a person builds it, and the lookups on it.
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

/// A Sketch of a 100 × 50 rectangle (dimensions "length" 100 and "width" 50, fully defined) → Extrude 6 → Hole Pattern (Ø8
/// through all, on a Linear Pattern of 2 at spacing 60 from (20, 25, 6)) → Output "Bracket". Added one edit at a time through
/// `DocumentModel.perform`, as `AppBracket` is.
@MainActor
struct AppSketchBracket {
    let app: AppModel
    private(set) var sketch = Node(typeID: "", name: "")
    private(set) var extrude = Node(typeID: "", name: "")
    private(set) var layout = Node(typeID: "", name: "")
    private(set) var holes = Node(typeID: "", name: "")
    private(set) var output = Node(typeID: "", name: "")
    /// The sketch's lines: bottom, right, top, left.
    private(set) var lines: [SketchEntityID] = []
    private(set) var lengthID = DimensionID(0)

    init(in app: AppModel) throws {
        self.app = app
        var drawing = Sketch(plane: .fixed(.xy))
        let corners = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 50), Vector2(0, 50)].map { drawing.addPoint($0) }
        lines = (0..<4).map { drawing.addLine(from: corners[$0], to: corners[($0 + 1) % 4]) }
        drawing.add(.horizontal(lines[0]))
        drawing.add(.horizontal(lines[2]))
        drawing.add(.vertical(lines[1]))
        drawing.add(.vertical(lines[3]))
        drawing.add(.fix(corners[0], at: .zero))
        lengthID = drawing.addDimension(.length(lines[0]), value: 100)
        let width = drawing.addDimension(.length(lines[1]), value: 50)
        drawing.renameDimension(lengthID, to: "length")
        drawing.renameDimension(width, to: "width")

        sketch = try add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        extrude = try add(ExtrudeNode.self, ["distance": .number(6)])
        try wire(sketch, "profiles", extrude, "profile")
        layout = try add(LinearPatternNode.self, ["start": .vector(Vector3(20, 25, 6)), "direction": .vector(.unitX),
                                                  "count": .integer(2), "spacing": .number(60), "facing": .vector(.unitZ),
                                                  ])
        holes = try add(HolePatternNode.self, ["diameter": .number(8), "throughAll": .bool(true)])
        try wire(extrude, "solid", holes, "part")
        try wire(layout, "placements", holes, "placements")
        output = try add(OutputNode.self)
        try wire(holes, "solid", output, "solid")
        try app.document.perform(.rename(output.id, "Bracket"))
    }

    private func add(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:]) throws -> Node {
        var node = app.registry.makeNode(definition.typeID, at: Vector2(Double(app.document.graph.nodes.count) * 40, 0))
        node.inputValues.merge(values) { _, given in given }
        try app.document.perform(.addNode(node))
        return node
    }

    private func wire(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) throws {
        try app.document.perform(.connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))))
    }

    /// The first dimension the viewport shows with `text`.
    func shown(_ app: AppModel, _ text: String) -> OverlayDimension? {
        app.viewport.dimensions.first { $0.text == text }
    }

    /// The solid `node` made, from the last evaluation.
    func solid(_ app: AppModel, of node: Node) -> Solid? {
        guard case .solid(let solid)? = app.document.results[node.id]?.outputs?["solid"]?.items.first else { return nil }
        return solid
    }

    /// The sketch as stored in the document.
    func storedSketch(_ app: AppModel) -> Sketch? {
        guard case .sketch(let stored)? = app.document.graph.nodes[sketch.id]?.inputValues[NodeSetting.sketch] else { return nil }
        return stored
    }

    /// The viewport item of the bracket: the one part shown whole.
    func index(_ app: AppModel) throws -> Int {
        try #require(app.viewport.items.firstIndex { !$0.isGhost && !$0.isGuide })
    }

    private func solid(_ app: AppModel) throws -> Solid { try app.viewport.items[index(app)].solid }

    private func holeWalls(_ app: AppModel) throws -> [FaceInfo] {
        try solid(app).topology.faces.filter { $0.kind == .cylinder }
    }

    /// A click on a hole's wall.
    func holeWall(_ app: AppModel) throws -> PickTarget {
        let wall = try #require(holeWalls(app).first)
        return .face(solid: try index(app), wall.id)
    }

    /// A click on the rim of the first hole, at the top.
    func holeRim(_ app: AppModel) throws -> PickTarget {
        let topology = try solid(app).topology
        let wall = try #require(holeWalls(app).first)
        let rims = topology.edges.filter { $0.kind == .circle && $0.faces.contains(wall.id) }
        let rim = try #require(rims.max { $0.midpoint.z < $1.midpoint.z })
        return .edge(solid: try index(app), rim.id)
    }

    /// The edge where the top cap meets the plate's wall `segment` (a sketch line's index).
    func plateTopEdge(_ app: AppModel, segment: Int) throws -> PickTarget {
        let topology = try solid(app).topology
        let cap = try #require(topology.faces.first { $0.tags.contains { $0.node == extrude.id && $0.role == .endCap } }?.id)
        let side = try #require(topology.faces.first { $0.tags.contains { $0.role == .side(segment: segment) } }?.id)
        let edge = try #require(topology.edges.first { Set($0.faces) == [cap, side] })
        return .edge(solid: try index(app), edge.id)
    }

    /// The sorted x of the centroids of the holes' walls.
    func holeCentresX(_ app: AppModel) throws -> [Double] {
        try holeWalls(app).map(\.centroid.x).sorted()
    }
}
#endif

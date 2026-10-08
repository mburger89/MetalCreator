// Test fixture file: the spec §7.2 bracket, built in an app the way a person builds it, and the checks on it.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// The §7.2 bracket's nodes, added to an app's document one edit at a time through `DocumentModel.perform`, the
/// path every editor gesture takes. The same recipe as `BracketAcceptanceTests.makeBracket()` in
/// CreatorNodesTests (which this target can't import), except that the chamfer's edges are picked in the app.
@MainActor
struct AppBracket {
    let app: AppModel
    let width: GraphParameter
    let holeCount: GraphParameter
    private(set) var plate = Node(typeID: "", name: "")
    private(set) var fillet = Node(typeID: "", name: "")
    private(set) var chamferEdges = Node(typeID: "", name: "")
    private(set) var chamfer = Node(typeID: "", name: "")
    private(set) var output = Node(typeID: "", name: "")

    init(in app: AppModel) throws {
        self.app = app
        width = GraphParameter(name: "Width", type: .number, value: .number(60), min: 20, max: 200)
        holeCount = GraphParameter(name: "Hole count", type: .integer, value: .integer(4), min: 0, max: 20)
        let wall = GraphParameter(name: "Wall", type: .number, value: .number(6), min: 1, max: 20)
        for parameter in [width, wall, holeCount] { try app.document.perform(.addParameter(parameter)) }
        let widthValue = try add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(width.id)])
        let wallValue = try add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(wall.id)])
        let holeValue = try add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(holeCount.id)])

        // 1. Rounded plate, Width × 40, R4, extruded by Wall.
        let plateProfile = try add(RoundedRectangleNode.self, ["height": .number(40), "cornerRadius": .number(4)])
        try wire(widthValue, "number", plateProfile, "width")
        plate = try add(ExtrudeNode.self)
        try wire(plateProfile, "profile", plate, "profile")
        try wire(wallValue, "number", plate, "distance")
        // 2. Holes: Grid Points (2 rows, Hole count points) → Circle Ø5 → Extrude → one subtract.
        let grid = try add(GridPointsNode.self, ["countY": .integer(2), "spacingX": .number(20), "spacingY": .number(16)])
        try wire(holeValue, "integer", grid, "total")
        let holeProfile = try add(CircleNode.self, ["diameter": .number(5)])
        try wire(grid, "points", holeProfile, "plane")
        let holes = try add(ExtrudeNode.self, ["distance": .number(20), "mode": .integer(1)])
        try wire(holeProfile, "profile", holes, "profile")
        let cut = try add(BooleanNode.self, ["operation": .integer(1)])
        try wire(plate, "solid", cut, "target")
        try wire(holes, "solid", cut, "tools")
        // 3. L-flange: a Width × 30 Rectangle on the XZ plane at y = 20, 8 thick, unioned.
        let flangePlane = try add(PlaneNode.self, ["orientation": .integer(1), "offset": .number(-20)])
        let flangeProfile = try add(RectangleNode.self, ["height": .number(30), "anchor": .integer(7)])
        try wire(widthValue, "number", flangeProfile, "width")
        try wire(flangePlane, "plane", flangeProfile, "plane")
        let flange = try add(ExtrudeNode.self, ["distance": .number(8)])
        try wire(flangeProfile, "profile", flange, "profile")
        let bracket = try add(BooleanNode.self)
        try wire(cut, "solid", bracket, "target")
        try wire(flange, "solid", bracket, "tools")
        // 4. Fillet R3 on Edges by Direction(Z) ∩ Edge Filter(convex); Chamfer 0.5 on picked plate top-cap edges.
        let vertical = try add(EdgesByDirectionNode.self)
        let convex = try add(EdgeFilterNode.self, ["convexity": .integer(1)])
        try wire(bracket, "solid", vertical, "solid")
        try wire(bracket, "solid", convex, "solid")
        let filletEdges = try add(EdgeSetOpNode.self, ["operation": .integer(2)])
        try wire(vertical, "edges", filletEdges, "a")
        try wire(convex, "edges", filletEdges, "b")
        fillet = try add(FilletNode.self, ["radius": .number(3)])
        try wire(filletEdges, "edges", fillet, "edges")
        chamferEdges = try add(EdgesByTagNode.self)
        try wire(fillet, "solid", chamferEdges, "solid")
        chamfer = try add(ChamferNode.self, ["distance": .number(0.5)])
        try wire(chamferEdges, "edges", chamfer, "edges")
        output = try add(OutputNode.self)
        try wire(chamfer, "solid", output, "solid")
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

    /// The plate's top-cap outline on `solid`: what a person clicks in pick mode for the chamfer.
    func topCapOutline(_ solid: Solid) -> [EdgeID] {
        let top = TopoTag(node: plate.id, item: 0, role: .endCap)
        func isPlateSide(_ face: FaceInfo) -> Bool {
            face.tags.contains { tag in
                guard tag.node == plate.id, case .side = tag.role else { return false }
                return true
            }
        }
        return solid.topology.edges.filter { edge in
            guard !edge.isSeam, edge.faces.count == 2,
                  let a = solid.topology.face(edge.faces[0]), let b = solid.topology.face(edge.faces[1]) else { return false }
            return (a.tags.contains(top) && isPlateSide(b)) || (b.tags.contains(top) && isPlateSide(a))
        }.map(\.id)
    }
}

/// Every node in `app` is `.ok`: no warning, no error, nothing idle (spec §7.2 step 6: "no node may show a warning").
@MainActor
func expectAllOK(_ app: AppModel, _ when: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let problems = app.document.results.compactMap { id, result -> String? in
        if case .ok = result.state { return nil }
        return "\(app.document.graph.nodes[id]?.name ?? "?"): \(result.state)"
    }
    #expect(problems.isEmpty, "\(when): \(problems.sorted().joined(separator: "; "))", sourceLocation: sourceLocation)
    #expect(app.document.results.count == app.document.graph.nodes.count, "\(when): every node is evaluated",
            sourceLocation: sourceLocation)
}

/// How many triangles use each undirected edge of an ASCII STL, after welding vertices to 1e-6 mm.
func edgeUseCounts(stl: String) -> [String: Int] {
    func key(_ line: Substring) -> String {
        let values = line.split(separator: " ").dropFirst().prefix(3).map { text -> Double in
            let rounded = ((Double(text) ?? .nan) * 1e6).rounded() / 1e6
            return rounded == 0 ? 0 : rounded
        }
        return values.map { "\($0)" }.joined(separator: ",")
    }
    let vertices = stl.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("vertex") }.map { key(Substring($0)) }
    var counts: [String: Int] = [:]
    for triangle in stride(from: 0, to: vertices.count - 2, by: 3) {
        let corners = [vertices[triangle], vertices[triangle + 1], vertices[triangle + 2]]
        for (a, b) in [(0, 1), (1, 2), (2, 0)] {
            counts[[corners[a], corners[b]].sorted().joined(separator: "|"), default: 0] += 1
        }
    }
    return counts
}

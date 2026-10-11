// Test fixture file: the patterns spec §7 benchmark's plate, built in an app on OCCT.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// A 210 × 110 × 6 plate with its top on z = 0 and a grid of Ø5 through-holes 10 mm apart (patterns spec §7): by default
/// 20 × 10 = 200, the spec's size. Three ways to make the same part:
/// - `.shortcut`: Grid Points → Points to Placements → Hole Pattern (through all);
/// - `.fillet`: the same, and an Edges by Tag + Fillet R0.5 on the rim of one patterned hole;
/// - `.explicit`: Grid Points → Points to Placements → Place, the Ø5 tool from a Circle and an Extrude, and one Boolean.
@MainActor
struct PatternBenchApp {
    enum Variant { case shortcut, fillet, explicit }

    /// The spec's 200 holes.
    static let columns = 20
    static let rows = 10
    static let plateVolume = 210.0 * 110 * 6

    let app: AppModel
    let kernel: OCCTKernel
    let columns: Int
    let rows: Int
    /// The node whose `diameter` the benchmark edits (the Hole Pattern, or the Circle of the explicit tool).
    private(set) var sizeNode = Node(typeID: "", name: "")
    private(set) var result = Node(typeID: "", name: "")
    private(set) var plate = Node(typeID: "", name: "")

    init(_ variant: Variant, columns: Int = Self.columns, rows: Int = Self.rows) async throws {
        kernel = OCCTKernel()
        app = AppModel(kernel: kernel)
        self.columns = columns
        self.rows = rows
        let profile = try add(RectangleNode.self, ["width": .number(210), "height": .number(110),
                                                   "plane": .plane(.through(Vector3(0, 0, -6))),
        ])
        plate = try add(ExtrudeNode.self, ["distance": .number(6)])
        try wire(profile, "profile", plate, "profile")
        let grid = try add(GridPointsNode.self, ["countX": .integer(columns), "countY": .integer(rows), "spacingX": .number(10),
                                                 "spacingY": .number(10),
        ])
        let placements = try add(PointsToPlacementsNode.self)
        try wire(grid, "points", placements, "points")
        switch variant {
        case .shortcut, .fillet:
            sizeNode = try add(HolePatternNode.self, ["diameter": .number(5), "throughAll": .bool(true)])
            try wire(plate, "solid", sizeNode, "part")
            try wire(placements, "placements", sizeNode, "placements")
            result = sizeNode
        case .explicit:
            sizeNode = try add(CircleNode.self, ["diameter": .number(5), "plane": .plane(Plane.xy.offset(by: -8))])
            let tool = try add(ExtrudeNode.self, ["distance": .number(9)])
            try wire(sizeNode, "profile", tool, "profile")
            let place = try add(PlaceNode.self)
            try wire(tool, "solid", place, "tool")
            try wire(placements, "placements", place, "placements")
            result = try add(BooleanNode.self, ["operation": .integer(1)])
            try wire(plate, "solid", result, "target")
            try wire(place, "solids", result, "tools")
        }
        var last = result
        if variant == .fillet {
            let rule = try add(EdgesByTagNode.self)
            try wire(result, "solid", rule, "solid")
            let fillet = try add(FilletNode.self, ["radius": .number(0.5)])
            try wire(rule, "edges", fillet, "edges")
            last = fillet
            // The pattern's result is only evaluated while something demands it: flag it as an output for the pick.
            try app.document.perform(.setOutput(result.id, true))
            await app.settle()
            try app.document.perform(.setInput(rule.id, NodeSetting.picks, .edgePicks(try pickOneRim(of: result))))
            try app.document.perform(.setOutput(result.id, false))
        }
        let output = try add(OutputNode.self)
        try wire(last, "solid", output, "solid")
        await app.settle()
    }

    /// The pick of the rim of one hole near the middle of the grid, on the plate's top, from the pattern's result.
    private func pickOneRim(of node: Node) throws -> [EdgePick] {
        let solid = try #require(solid(of: node))
        let index = (rows / 2) * columns + columns / 2
        let bore = TopoTag(node: NodeID.instanceScoped([node.id, node.id]), item: index, role: .side(segment: 1))
        let top = TopoTag(node: plate.id, item: 0, role: .endCap)
        let rim = try #require(solid.topology.edges.first { edge in
            guard edge.kind == .circle, !edge.isSeam, edge.faces.count == 2 else { return false }
            let sides = edge.faces.compactMap { solid.topology.face($0) }
            return sides.contains { $0.tags.contains(bore) } && sides.contains { $0.tags.contains(top) }
        })
        return solid.topology.picks(for: [rim.id])
    }

    /// The part the pattern made.
    var part: Solid? { solid(of: result) }

    /// The solid on `node`'s `solid` output.
    func solid(of node: Node) -> Solid? {
        app.document.results[node.id]?.outputs?["solid"]?.items.lazy.compactMap { scalar -> Solid? in
            if case .solid(let solid) = scalar { solid } else { nil }
        }.first
    }

    /// Sets the holes' diameter and waits for the evaluation, the scene and its meshes.
    func setDiameter(_ diameter: Double) async throws {
        try app.document.perform(.setInput(sizeNode.id, "diameter", .number(diameter)))
        await app.settle()
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
}

import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorOCCT

/// Spec §7.2, headless: the parametric mounting bracket built only from the 26 nodes, evaluated
/// by a `DocumentModel` on `OCCTKernel`, re-parameterised, saved, reopened and exported.
@MainActor
struct BracketAcceptanceTests {
    /// The bracket graph and the nodes the test inspects.
    struct Bracket {
        var graph: Graph
        let width: GraphParameter
        let holeCount: GraphParameter
        let plate: Node
        let cut: Node
        let holes: Node
        /// The L-flange: its plane, its Rectangle profile, its Extrude and the union that joins it to the plate.
        let flangePlane: Node
        let flangeProfile: Node
        let flange: Node
        let union: Node
        let filletEdges: Node
        let fillet: Node
        let chamferEdges: Node
        let output: Node
    }

    static func makeBracket() -> Bracket {
        var h = Harness()
        let width = GraphParameter(name: "Width", type: .number, value: .number(60), min: 20, max: 200)
        let wall = GraphParameter(name: "Wall", type: .number, value: .number(6), min: 1, max: 20)
        // min 0 is safe: at 0 holes Boolean passes the plate through (Task 9, `anEmptyToolListLeavesTheTargetUnchanged`).
        let holeCount = GraphParameter(name: "Hole count", type: .integer, value: .integer(4), min: 0, max: 20)
        h.parameters = [width, wall, holeCount]
        func parameter(_ p: GraphParameter) -> Node {
            h.add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(p.id)])
        }
        let widthValue = parameter(width), wallValue = parameter(wall), holeValue = parameter(holeCount)

        // 1. Rounded plate, Width × 40, R4, extruded by Wall.
        let plateProfile = h.add(RoundedRectangleNode.self, ["height": .number(40), "cornerRadius": .number(4)])
        h.wire(widthValue, "number", to: plateProfile, "width")
        let plate = h.add(ExtrudeNode.self)
        h.wire(plateProfile, "profile", to: plate, "profile")
        h.wire(wallValue, "number", to: plate, "distance")

        // 2. Holes: Grid Points (2 rows, Hole count points) → Circle Ø5 → Extrude → one subtract.
        let grid = h.add(GridPointsNode.self, ["countY": .integer(2), "spacingX": .number(20), "spacingY": .number(16)])
        h.wire(holeValue, "integer", to: grid, "total")
        let holeProfile = h.add(CircleNode.self, ["diameter": .number(5)])
        h.wire(grid, "points", to: holeProfile, "plane")
        let holes = h.add(ExtrudeNode.self, ["distance": .number(20), "mode": .integer(1)])
        h.wire(holeProfile, "profile", to: holes, "profile")
        let cut = h.add(BooleanNode.self, ["operation": .integer(1)])
        h.wire(plate, "solid", to: cut, "target")
        h.wire(holes, "solid", to: cut, "tools")

        // 3. L-flange: a Width × 30 Rectangle standing on the back edge (XZ plane at y = 20), 8 thick.
        let flangePlane = h.add(PlaneNode.self, ["orientation": .integer(1), "offset": .number(-20)])
        let flangeProfile = h.add(RectangleNode.self, ["height": .number(30), "anchor": .integer(7)])
        h.wire(widthValue, "number", to: flangeProfile, "width")
        h.wire(flangePlane, "plane", to: flangeProfile, "plane")
        let flange = h.add(ExtrudeNode.self, ["distance": .number(8)])
        h.wire(flangeProfile, "profile", to: flange, "profile")
        let bracket = h.add(BooleanNode.self)
        h.wire(cut, "solid", to: bracket, "target")
        h.wire(flange, "solid", to: bracket, "tools")

        // 4. Fillet R3 on Edges by Direction(Z) ∩ Edge Filter(convex); Chamfer 0.5 on picked top-cap edges.
        let vertical = h.add(EdgesByDirectionNode.self)
        let convex = h.add(EdgeFilterNode.self, ["convexity": .integer(1)])
        h.wire(bracket, "solid", to: vertical, "solid")
        h.wire(bracket, "solid", to: convex, "solid")
        let filletEdges = h.add(EdgeSetOpNode.self, ["operation": .integer(2)])
        h.wire(vertical, "edges", to: filletEdges, "a")
        h.wire(convex, "edges", to: filletEdges, "b")
        let fillet = h.add(FilletNode.self, ["radius": .number(3)])
        h.wire(filletEdges, "edges", to: fillet, "edges")
        let chamferEdges = h.add(EdgesByTagNode.self)
        h.wire(fillet, "solid", to: chamferEdges, "solid")
        let chamfer = h.add(ChamferNode.self, ["distance": .number(0.5)])
        h.wire(chamferEdges, "edges", to: chamfer, "edges")
        let output = h.add(OutputNode.self)
        h.wire(chamfer, "solid", to: output, "solid")

        return Bracket(graph: h.graph, width: width, holeCount: holeCount, plate: plate, cut: cut, holes: holes,
                       flangePlane: flangePlane, flangeProfile: flangeProfile, flange: flange, union: bracket,
                       filletEdges: filletEdges, fillet: fillet, chamferEdges: chamferEdges, output: output)
    }

    /// What the viewport's pick would select: edges between the plate's top cap and a plate side.
    func topCapOutline(_ solid: Solid, plate: Node) -> [EdgeID] {
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

    func edgeSet(_ document: DocumentModel, _ node: Node) throws -> EdgeSet {
        try #require(document.results[node.id]?.outputs?["edges"]?.edgeSets?.first)
    }

    func keys(_ set: EdgeSet) -> Set<EdgeKey> {
        Set(set.edges.compactMap { id in set.solid.topology.edge(id).flatMap(set.solid.topology.key(of:)) })
    }

    /// Every evaluated node is `.ok`: no warning, no error, nothing idle.
    func expectAllOK(_ document: DocumentModel, _ when: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let problems = document.results.compactMap { id, result -> String? in
            if case .ok = result.state { return nil }
            return "\(document.graph.nodes[id]?.name ?? "?"): \(result.state)"
        }
        #expect(problems.isEmpty, "\(when): \(problems.sorted().joined(separator: "; "))", sourceLocation: sourceLocation)
        #expect(document.results.count == document.graph.nodes.count, "\(when): every node is upstream of the output",
                sourceLocation: sourceLocation)
    }

    @Test func bracketKeepsItsEdgeSelectionsAcrossParameterChangesAndExports() async throws {
        let kernel = OCCTKernel()
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()

        // Nothing picked yet: the rule asks for a pick and the chamfer has no edges.
        #expect(document.results[bracket.chamferEdges.id]?.state == .warning("Pick edges in view to fill this rule."))
        let filleted = try #require(document.results[bracket.fillet.id]?.outputs?["solid"]?.solids?.first)
        let picked = topCapOutline(filleted, plate: bracket.plate)
        #expect(picked.count == 7)
        // As the M6 app shell will: viewport-picked IDs → `Topology.picks(for:)` → `.edgePicks`.
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks,
                                       .edgePicks(filleted.topology.picks(for: picked))))
        await document.waitForEvaluation()
        expectAllOK(document, "Width 60, 4 holes")
        let filletKeys = keys(try edgeSet(document, bracket.filletEdges))
        let chamferKeys = keys(try edgeSet(document, bracket.chamferEdges))
        #expect(try edgeSet(document, bracket.filletEdges).edges.count == 4)
        #expect(try edgeSet(document, bracket.chamferEdges).edges.count == 7)

        // Width 60 → 90 and Hole count 4 → 6 (2 × 3).
        try document.perform(.setParameter(bracket.width.id, .number(90)))
        try document.perform(.setParameter(bracket.holeCount.id, .integer(6)))
        await document.waitForEvaluation()
        expectAllOK(document, "Width 90, 6 holes")
        #expect(keys(try edgeSet(document, bracket.filletEdges)) == filletKeys)
        #expect(keys(try edgeSet(document, bracket.chamferEdges)) == chamferKeys)
        #expect(try edgeSet(document, bracket.filletEdges).edges.count == 4)
        #expect(try edgeSet(document, bracket.chamferEdges).edges.count == 7)
        let cut = try #require(document.results[bracket.cut.id]?.outputs?["solid"]?.solids?.first)
        for item in 0..<6 {
            #expect(cut.topology.faces.contains { $0.tags.contains(TopoTag(node: bracket.holes.id, item: item, role: .side(segment: 0))) })
        }
        let solids = try #require(document.results[bracket.output.id]?.outputs?["solid"]?.solids)
        let part = try #require(solids.first)
        #expect(solids.count == 1)
        #expect(isClose(part.bounds.size.x, 90, relative: 1e-6))

        // Save and reopen: the picks survive the file, and nothing warns.
        let reopened = try DocumentModel(data: try document.fileData(), registry: BuiltInNodes.registry, kernel: kernel)
        await reopened.waitForEvaluation()
        expectAllOK(reopened, "reopened")
        #expect(keys(try edgeSet(reopened, bracket.chamferEdges)) == chamferKeys)

        // Export STEP (re-read through OCCT) and STL (closed and manifold).
        let step = URL.temporaryDirectory.appending(path: "bracket-\(UUID().uuidString).step")
        let stl = URL.temporaryDirectory.appending(path: "bracket-\(UUID().uuidString).stl")
        defer {
            try? FileManager.default.removeItem(at: step)
            try? FileManager.default.removeItem(at: stl)
        }
        try await kernel.export(solids, format: .step, to: step)
        try await kernel.export(solids, format: .stl, to: stl)
        let readVolume = try OCCTKernel.serialized { () throws -> Double in try OCCTShape.readSTEP(step).properties().volume }
        #expect(isClose(readVolume, try await volume(part, kernel), relative: 1e-5))
        let counts = edgeUseCounts(stl: try String(contentsOf: stl, encoding: .utf8))
        #expect(!counts.isEmpty)
        #expect(counts.values.allSatisfy { $0 == 2 }, "every STL edge is shared by exactly two triangles")
    }

    /// Counts how many triangles use each undirected edge, after welding vertices to 1e-6 mm.
    func edgeUseCounts(stl: String) -> [String: Int] {
        func key(_ line: Substring) -> String {
            let values = line.split(separator: " ").dropFirst().prefix(3).map { text -> Double in
                let rounded = ((Double(text) ?? .nan) * 1e6).rounded() / 1e6
                return rounded == 0 ? 0 : rounded
            }
            return "\(values[0]),\(values[1]),\(values[2])"
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
}

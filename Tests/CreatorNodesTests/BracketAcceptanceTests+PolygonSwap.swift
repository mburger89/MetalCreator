import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// Spec §8's third naming-stability case (spec Errata (M3), (M6), (naming: merged faces)): the L-flange's
    /// Rectangle swapped for a Regular Polygon on the same plane, a hexagon of radius 15 turned 30° so two of
    /// its sides stand parallel to Z, lifted 15 mm by a Transform so it stands on the plate. What holds, pinned
    /// here:
    /// - the fillet's rule re-derives its edges: 4 again, now the hexagon's vertical side edges on its two caps;
    /// - every chamfer pick resolves, with no warning: the three that name only plate faces to the same edges,
    ///   and the two on the plate sides the union had merged with the rectangle's coplanar sides, recorded with
    ///   the rectangle's side tags, to the plate's whole side edges by their narrowed keys (`EdgeKey.narrowed`);
    ///   the rectangle's fillet had split each of those edges in two, the hexagon doesn't, and that is not drift
    ///   (`EdgePick.runCount`);
    /// - OCCT still can't chamfer them: its fillet of the hexagon's vertical edges returns a solid that
    ///   OCCT's own checker rejects (`BRepCheck_Analyzer`, probe in the naming-merged-faces plan), and every
    ///   blend along the top outline's tangent chain fails on it, so the Chamfer is in error and the Output has
    ///   no result. The same resolved edges chamfer on the union before the fillet. Owner: roadmap row
    ///   "Kernel: blends that return an invalid solid";
    /// - one undo brings the rectangle flange, both edge sets and the part back.
    @Test func swappingTheFlangeForAPolygonKeepsEveryPickButTheFilletedHexagonCantBeChamfered() async throws {
        let kernel = OCCTKernel()
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let filleted = try #require(document.results[bracket.fillet.id]?.outputs?["solid"]?.solids?.first)
        let picks = filleted.topology.picks(for: topCapOutline(filleted, plate: bracket.plate))
        #expect(picks.count == 5)
        #expect(picks.filter { $0.matchCount == 2 && $0.runCount == 1 }.count == 2, "the two split plate-side edges")
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks, .edgePicks(picks)))
        await document.waitForEvaluation()
        expectAllOK(document, "rectangle flange")
        let chamferKeys = keys(try edgeSet(document, bracket.chamferEdges))
        let filletKeys = keys(try edgeSet(document, bracket.filletEdges))

        try swapTheFlangeForAHexagon(in: document, bracket)
        await document.waitForEvaluation()

        #expect(document.results[bracket.fillet.id]?.state.isSuccess == true)
        let fillet = try edgeSet(document, bracket.filletEdges)
        #expect(fillet.edges.count == 4)
        #expect(keys(fillet) != filletKeys, "the fillet's flange keys are re-derived from the polygon")
        let sideX = 15 * 3.0.squareRoot() / 2   // r cos 30°
        #expect(fillet.edges.allSatisfy { id in
            fillet.solid.topology.edge(id).map { isClose(abs($0.midpoint.x), sideX, relative: 1e-6) } ?? false
        }, "every fillet edge is on one of the hexagon's vertical sides")

        let chamfer = try edgeSet(document, bracket.chamferEdges)
        guard case .ok? = document.results[bracket.chamferEdges.id]?.state else {
            Issue.record("Edges by Tag: \(String(describing: document.results[bracket.chamferEdges.id]?.state))"); return
        }
        #expect(chamfer.edges.count == 5)
        #expect(keys(chamfer) == Set(chamferKeys.map { $0.narrowed ?? $0 }), "the merged-side picks resolve narrowed")
        let outline = chamfer.edges.compactMap { chamfer.solid.topology.edge($0) }
        #expect(outline.allSatisfy { isClose($0.midpoint.z, 6, relative: 1e-9) && $0.midpoint.y <= 1e-6 },
                "the front edge, its corners and the two sides of the plate's top; not its back")
        #expect(outline.filter { isClose($0.length, 32, relative: 1e-9) }.count == 2, "each side edge is whole")

        let chamferNode = try #require(document.graph.nodes.values.first { $0.typeID == ChamferNode.typeID })
        guard case .error(let reason)? = document.results[chamferNode.id]?.state else {
            Issue.record("OCCT is expected to refuse the chamfer on the filleted hexagon"); return
        }
        #expect(reason.hasPrefix("Chamfer failed"))
        #expect(document.results[bracket.output.id]?.outputs == nil, "the Output has no part to show or export")
        // The picks are not what fails: the same resolved edges chamfer on the union, before the fillet.
        let union = try #require(document.results[bracket.union.id]?.outputs?["solid"]?.solids?.first)
        let resolved = picks.flatMap { union.topology.edges(resolving: $0.key) }.map(\.id)
        #expect(resolved.count == 5)
        _ = try await kernel.chamfer(union, edges: resolved, distance: 0.5, tag: NodeTag(node: NodeID(), item: 0))

        document.undo()
        await document.waitForEvaluation()
        expectAllOK(document, "undone")
        #expect(document.results[bracket.output.id]?.outputs?["solid"]?.solids?.count == 1)
        #expect(keys(try edgeSet(document, bracket.filletEdges)) == filletKeys)
        #expect(keys(try edgeSet(document, bracket.chamferEdges)) == chamferKeys)
    }

    /// Replaces the flange's Rectangle with a hexagon (r 15, turned 30°) lifted 15 mm, as one undo step:
    /// removing the Rectangle drops its three wires, and the lifted flange replaces the old one in the union's
    /// tools.
    func swapTheFlangeForAHexagon(in document: DocumentModel, _ bracket: Bracket) throws {
        var polygon = BuiltInNodes.registry.makeNode(RegularPolygonNode.typeID)
        polygon.inputValues.merge(["sides": .integer(6), "radius": .number(15), "rotation": .number(30)]) { _, new in new }
        var lift = BuiltInNodes.registry.makeNode(TransformNode.typeID)
        lift.inputValues["move"] = .vector(Vector3(0, 0, 15))
        func link(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) -> GraphCommand {
            .connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input)))
        }
        try document.perform(.batch([
            .addNode(polygon), .addNode(lift), .removeNode(bracket.flangeProfile.id),
            link(bracket.flangePlane, "plane", polygon, "plane"), link(polygon, "profile", bracket.flange, "profile"),
            link(bracket.flange, "solid", lift, "solid"), link(lift, "solid", bracket.union, "tools"),
        ]))
    }
}

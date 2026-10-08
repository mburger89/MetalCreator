import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// Spec §8's third naming-stability case, owned by M6 (spec Errata (M3), (M6)): the L-flange's Rectangle
    /// swapped for a Regular Polygon on the same plane, a hexagon of radius 15 turned 30° so two of its sides
    /// stand parallel to Z, lifted 15 mm by a Transform so it stands on the plate. What holds, pinned here:
    /// - the fillet's rule re-derives its edges: 4 again, now the hexagon's vertical side edges on its two caps;
    /// - the chamfer's three picks that name only plate faces (the front edge and front corners) resolve to
    ///   the same edges;
    /// - the two picks on the plate sides the union had merged with the rectangle's coplanar sides name the
    ///   rectangle's side tags, so they match nothing now and Edges by Tag says so (spec §5.3 rule 6: no silent
    ///   drift);
    /// - OCCT refuses to chamfer the three edges that are left (a partial chain), so the Chamfer is in error and
    ///   the Output has no result: the part is gone until the user re-picks (spec Errata (M6), Decision 9 of the
    ///   M6 plan, signed off by the user (2026-10-07));
    /// - one undo brings the rectangle flange, both edge sets and the part back.
    @Test func swappingTheFlangeRectangleForAPolygonRederivesTheFilletAndFlagsTheChamferDrift() async throws {
        let kernel = OCCTKernel()
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let filleted = try #require(document.results[bracket.fillet.id]?.outputs?["solid"]?.solids?.first)
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks,
                                       .edgePicks(filleted.topology.picks(for: topCapOutline(filleted, plate: bracket.plate)))))
        await document.waitForEvaluation()
        expectAllOK(document, "rectangle flange")
        let chamferKeys = keys(try edgeSet(document, bracket.chamferEdges))
        let filletKeys = keys(try edgeSet(document, bracket.filletEdges))

        var polygon = BuiltInNodes.registry.makeNode(RegularPolygonNode.typeID)
        polygon.inputValues.merge(["sides": .integer(6), "radius": .number(15), "rotation": .number(30)]) { _, new in new }
        var lift = BuiltInNodes.registry.makeNode(TransformNode.typeID)
        lift.inputValues["move"] = .vector(Vector3(0, 0, 15))
        func link(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) -> GraphCommand {
            .connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input)))
        }
        // One undo step: removing the Rectangle drops its three wires, and the lifted flange replaces the old
        // one in the union's tools.
        try document.perform(.batch([
            .addNode(polygon), .addNode(lift), .removeNode(bracket.flangeProfile.id),
            link(bracket.flangePlane, "plane", polygon, "plane"), link(polygon, "profile", bracket.flange, "profile"),
            link(bracket.flange, "solid", lift, "solid"), link(lift, "solid", bracket.union, "tools"),
        ]))
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
        #expect(chamfer.edges.count == 3)
        #expect(keys(chamfer).isSubset(of: chamferKeys), "the plate-only picks resolve unchanged")
        #expect(document.results[bracket.chamferEdges.id]?.state == .warning("Matched 0 edges, expected 2; 0 edges, expected 2."))
        let chamferNode = try #require(document.graph.nodes.values.first { $0.typeID == ChamferNode.typeID })
        guard case .error(let reason)? = document.results[chamferNode.id]?.state else {
            Issue.record("the chamfer of the three remaining edges is expected to fail"); return
        }
        #expect(reason.hasPrefix("Chamfer failed"))
        #expect(document.results[bracket.output.id]?.outputs == nil, "the Output has no part to show or export")
        #expect(document.results[bracket.output.id]?.state.isSuccess == false)

        document.undo()
        await document.waitForEvaluation()
        expectAllOK(document, "undone")
        #expect(document.results[bracket.output.id]?.outputs?["solid"]?.solids?.count == 1)
        #expect(keys(try edgeSet(document, bracket.filletEdges)) == filletKeys)
        #expect(keys(try edgeSet(document, bracket.chamferEdges)) == chamferKeys)
    }
}

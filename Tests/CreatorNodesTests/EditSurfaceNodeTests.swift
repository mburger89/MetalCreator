import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

#if canImport(CreatorOCCT)
/// A one-face B-spline sheet with a `uCount` x `vCount` net (the kernel's test helper), for the Edit Surface tests.
private enum NetSheetNode: NodeDefinition {
    static let typeID = "test.netSheet"
    static let displayName = "Net Sheet"
    static let category = NodeCategory.surface
    static let inputs = [SocketSpec("u", .integer, defaultValue: .integer(6)), SocketSpec("v", .integer, defaultValue: .integer(8))]
    static let outputs = [SocketSpec("surface", .solid)]
    static let kernel = OCCTKernel()

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let sheet = try await Self.kernel.bsplineSheet(uCount: try inputs.integer("u"), vCount: try inputs.integer("v"), degree: 1,
                                                       tag: context.tag)
        return NodeOutputs(["surface": .solid(sheet)])
    }
}

/// NS-3 Task 5: the Edit Surface and Edit Curve nodes.
struct EditSurfaceNodeTests {
    let kernel = OCCTKernel()
    let registry = NodeRegistry(BuiltInNodes.all + [NetSheetNode.self])

    func run(_ moves: [PoleMove], u: Int = 6, v: Int = 8) async throws -> (EvaluationReport, Node, Node, Node) {
        let source = registry.makeNode(NetSheetNode.typeID, at: .zero)
        var edit = registry.makeNode(EditSurfaceNode.typeID)
        edit.inputValues[NodeSetting.poleMoves] = .poleMoves(moves)
        var source2 = source
        source2.inputValues["u"] = .integer(u)
        source2.inputValues["v"] = .integer(v)
        let link = Link(from: Endpoint(node: source2.id, socket: "surface"), to: Endpoint(node: edit.id, socket: "surface"))
        let graph = Graph(nodes: [source2.id: source2, edit.id: edit], links: [link])
        let report = try await Evaluator(registry: registry, kernel: kernel)
            .evaluate(graph, demand: [edit.id], images: ImageResolver())
        return (report, source2, edit, edit)
    }

    func pole(_ solid: Solid, _ i: Int, _ j: Int) async throws -> Vector3 {
        let net = try await kernel.controlNet(of: solid).surface
        return net.poles[i * net.vCount + j]
    }

    func move(_ i: Int, _ j: Int, _ offset: Vector3) -> PoleMove { PoleMove(index: PoleIndex(i: i, j: j), offset: offset) }

    @Test func theNodesAreRegistered() {
        #expect(EditSurfaceNode.category == .surface && EditSurfaceNode.librarySubgroup == "Make")
        #expect(EditCurveNode.category == .surface && EditCurveNode.librarySubgroup == "Make")
        #expect(EditSurfaceNode.factsTitle == "Surface" && EditCurveNode.factsTitle == "Curve")
        #expect(EditSurfaceNode.readsScrubbing == false)
        #expect(registry.makeNode(EditSurfaceNode.typeID).inputValues[NodeSetting.poleMoves] == .poleMoves([]))
        #expect(registry.makeNode(EditCurveNode.typeID).inputValues[NodeSetting.poleMoves] == .poleMoves([]))
    }

    @Test func noMovesPassesTheSurfaceThrough() async throws {
        let (report, source, edit, _) = try await run([])
        let before = try #require(report.value(source, "surface")?.solids?.first)
        let after = try #require(report.value(edit, "surface")?.solids?.first)
        #expect(before === after)
        #expect(report.isOK(edit))
    }

    @Test func aMoveMovesThePole() async throws {
        let (report, source, edit, _) = try await run([move(2, 3, Vector3(0, 0, 0.3))])
        let before = try #require(report.value(source, "surface")?.solids?.first)
        let after = try #require(report.value(edit, "surface")?.solids?.first)
        #expect(report.isOK(edit), "\(String(describing: report.state(edit)))")
        let delta = try await pole(after, 2, 3) - pole(before, 2, 3)
        #expect((delta - Vector3(0, 0, 0.3)).length < 1e-9)
        #expect(report.isOK(edit))
    }

    @Test func staleMovesWarnAndStayInTheSetting() async throws {
        let moves = [move(7, 0, Vector3(0, 0, 1)), move(0, 9, Vector3(0, 0, 1)), move(1, 1, Vector3(0, 0, 0.2))]
        let (report, source, edit, _) = try await run(moves)
        #expect(report.warning(edit) == "2 control point moves no longer fit the surface's 6 × 8 net.")
        let before = try #require(report.value(source, "surface")?.solids?.first)
        let after = try #require(report.value(edit, "surface")?.solids?.first)
        #expect(try await (pole(after, 1, 1) - pole(before, 1, 1) - Vector3(0, 0, 0.2)).length < 1e-9)
        // Evaluation never rewrites the setting.
        #expect(edit.inputValues[NodeSetting.poleMoves]?.poleMoves?.count == 3)
    }

    @Test func oneStaleMoveIsSingular() async throws {
        let (report, _, edit, _) = try await run([move(7, 0, Vector3(0, 0, 1))])
        #expect(report.warning(edit) == "1 control point move no longer fits the surface's 6 × 8 net.")
    }

    @Test func aFoldWarns() async throws {
        let folded = try await run([move(0, 0, Vector3(6, 6, 0))], u: 3, v: 3)
        #expect(folded.0.warning(folded.2)
                == "The moved surface folds over itself; zebra stripes, thickening and offsets will misbehave there.")
        let plain = try await run([move(1, 1, Vector3(0, 0, 1))], u: 3, v: 3)
        #expect(plain.0.isOK(plain.2))
    }

    @Test func factsListTheNet() async throws {
        let (report, _, edit, _) = try await run([])
        let facts = try #require(report.results[edit.id]?.facts)
        #expect(facts == [
            PayloadFact("Degree", "1 × 1"), PayloadFact("Control points", "6 × 8"), PayloadFact("Knots", "6 × 8"),
            PayloadFact("Rational", "no"),
        ])
    }

    @Test func picksDownstreamSurvive() async throws {
        // A planar sheet is converted to its exact 2 x 2 net; its boundary edges carry the Planar Surface node's names.
        let rect = registry.makeNode(RectangleNode.typeID)
        var rectangle = rect
        rectangle.inputValues["width"] = .number(10)
        rectangle.inputValues["height"] = .number(20)
        let planar = registry.makeNode(PlanarSurfaceNode.typeID)
        var edit = registry.makeNode(EditSurfaceNode.typeID)
        let byTag = registry.makeNode(EdgesByTagNode.typeID)
        let links = [
            Link(from: Endpoint(node: rectangle.id, socket: "profile"), to: Endpoint(node: planar.id, socket: "curves")),
            Link(from: Endpoint(node: planar.id, socket: "surface"), to: Endpoint(node: edit.id, socket: "surface")),
            Link(from: Endpoint(node: edit.id, socket: "surface"), to: Endpoint(node: byTag.id, socket: "solid")),
        ]
        func evaluate(_ edit: Node, _ byTag: Node) async throws -> EvaluationReport {
            let nodes = [rectangle.id: rectangle, planar.id: planar, edit.id: edit, byTag.id: byTag]
            return try await Evaluator(registry: registry, kernel: kernel)
                .evaluate(Graph(nodes: nodes, links: links), demand: [byTag.id], images: ImageResolver())
        }
        let first = try await evaluate(edit, byTag)
        let sheet = try #require(first.value(edit, "surface")?.solids?.first)
        let right = try #require(sheet.topology.edges.first { $0.midpoint.x > 4.9 && abs($0.midpoint.y) < 1e-6 })
        var picking = byTag
        picking.inputValues[NodeSetting.picks] = .edgePicks(sheet.topology.picks(for: [right.id]))
        edit.inputValues[NodeSetting.poleMoves] = .poleMoves([move(0, 0, Vector3(0, 0, 3))])
        let report = try await evaluate(edit, picking)
        let moved = try #require(report.value(edit, "surface")?.solids?.first)
        #expect(moved !== sheet)
        let set = try #require(report.value(picking, "edges")?.edgeSets?.first)
        #expect(report.isOK(picking) && set.edges.count == 1, "\(String(describing: report.state(picking)))")
        let edge = try #require(set.solid.topology.edges.first { $0.id == set.edges.first })
        #expect(abs(edge.midpoint.x - 5) < 1e-6)
    }

    @Test func editCurveMovesAPole() async throws {
        let series = registry.makeNode(SeriesNode.typeID)
        var seriesNode = series
        seriesNode.inputValues["step"] = .number(10)
        seriesNode.inputValues["count"] = .integer(5)
        var vector = registry.makeNode(VectorNode.typeID)
        vector.inputValues["y"] = .number(0)
        let through = registry.makeNode(CurveThroughPointsNode.typeID)
        var edit = registry.makeNode(EditCurveNode.typeID)
        edit.inputValues[NodeSetting.poleMoves] = .poleMoves([move(2, 0, Vector3(0, 0, 5)), move(40, 0, Vector3(0, 0, 1))])
        let links = [
            Link(from: Endpoint(node: seriesNode.id, socket: "values"), to: Endpoint(node: vector.id, socket: "x")),
            Link(from: Endpoint(node: vector.id, socket: "vector"), to: Endpoint(node: through.id, socket: "points")),
            Link(from: Endpoint(node: through.id, socket: "curve"), to: Endpoint(node: edit.id, socket: "curve")),
        ]
        let nodes = [seriesNode.id: seriesNode, vector.id: vector, through.id: through, edit.id: edit]
        let report = try await Evaluator(registry: registry, kernel: kernel)
            .evaluate(Graph(nodes: nodes, links: links), demand: [edit.id], images: ImageResolver())
        let before = try #require(report.value(through, "curve")?.curves?.first)
        let after = try #require(report.value(edit, "curve")?.curves?.first)
        let poles = try await kernel.controlNet(of: before).curve.poles
        let moved = try await kernel.controlNet(of: after).curve.poles
        #expect((moved[2] - poles[2] - Vector3(0, 0, 5)).length < 1e-9)
        #expect(report.warning(edit) == "1 control point move no longer fits the curve's \(poles.count) control points.")
    }

    @Test func theButtonIsFirst() {
        #expect(EditSurfaceNode.inspector.first?.controls.first == .button(title: "Edit Control Points", action: .editControlPoints))
        #expect(EditCurveNode.inspector.first?.controls.first == .button(title: "Edit Control Points", action: .editControlPoints))
    }
}
#endif

import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

#if canImport(CreatorOCCT)
/// A one-face B-spline sheet with a `u` x `v` net of degree 1 (the kernel's test helper).
private enum RebuildSourceNode: NodeDefinition {
    static let typeID = "test.rebuildSource"
    static let displayName = "Rebuild Source"
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

/// NS-3 Task 6: the Rebuild Surface and Rebuild Curve nodes.
struct RebuildNodeTests {
    let kernel = OCCTKernel()
    let registry = NodeRegistry(BuiltInNodes.all + [RebuildSourceNode.self])

    /// Source, then (when `bump` is set) an Edit Surface that lifts one pole 5 mm so the sheet is not flat, then the rebuild.
    func rebuild(_ settings: [SocketName: ConstantValue] = [:], bump: Bool = false) async throws -> (EvaluationReport, Node, Node) {
        let source = registry.makeNode(RebuildSourceNode.typeID)
        var node = registry.makeNode(RebuildSurfaceNode.typeID)
        for (key, value) in settings { node.inputValues[key] = value }
        var nodes = [source.id: source, node.id: node]
        var links: [Link] = []
        var from = source
        if bump {
            var edit = registry.makeNode(EditSurfaceNode.typeID)
            edit.inputValues[NodeSetting.poleMoves] = .poleMoves([PoleMove(index: PoleIndex(i: 2, j: 3), offset: Vector3(0, 0, 5))])
            nodes[edit.id] = edit
            links.append(Link(from: Endpoint(node: source.id, socket: "surface"), to: Endpoint(node: edit.id, socket: "surface")))
            from = edit
        }
        links.append(Link(from: Endpoint(node: from.id, socket: "surface"), to: Endpoint(node: node.id, socket: "surface")))
        let report = try await Evaluator(registry: registry, kernel: kernel)
            .evaluate(Graph(nodes: nodes, links: links), demand: [node.id], images: ImageResolver())
        return (report, source, node)
    }

    func deviationFact(_ report: EvaluationReport, _ node: Node) -> String? {
        report.results[node.id]?.facts.first { $0.label == "Deviation" }?.value
    }

    @Test func theNodesAreRegistered() {
        #expect(RebuildSurfaceNode.category == .surface && RebuildSurfaceNode.librarySubgroup == "Make")
        #expect(RebuildCurveNode.category == .surface && RebuildCurveNode.librarySubgroup == "Make")
        #expect(RebuildSurfaceNode.typeID == "creator.rebuildSurface" && RebuildCurveNode.typeID == "creator.rebuildCurve")
        let defaults = RebuildSurfaceNode.inputs.map(\.defaultValue)
        #expect(defaults == [nil, .integer(3), .integer(3), .integer(4), .integer(4), .number(0.01)])
        #expect(RebuildCurveNode.inputs.map(\.defaultValue) == [nil, .integer(3), .integer(8), .number(0.01)])
    }

    @Test func aRebuildReportsItsDeviation() async throws {
        let (report, _, node) = try await rebuild(["tolerance": .number(1000)])
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        let facts = try #require(report.results[node.id]?.facts)
        #expect(facts.prefix(2) == [PayloadFact("Degree", "3 × 3"), PayloadFact("Control points", "7 × 7")])
        let solid = try #require(report.value(node, "surface")?.solids?.first)
        let reported = try await kernel.rebuilt(solid, as: RebuildSpec(degreeU: 3, degreeV: 3, spansU: 4, spansV: 4)).deviation
        #expect(reported >= 0)
        #expect(deviationFact(report, node) != nil)
        #expect(report.warning(node) == nil)
    }

    @Test func aDeviationAboveToleranceWarns() async throws {
        // A net of degree 1 with six by eight poles is rebuilt as a single cubic span: it can't follow it closely.
        let settings: [SocketName: ConstantValue] = ["spansU": .integer(1), "spansV": .integer(1), "tolerance": .number(0.0001)]
        let (report, _, node) = try await rebuild(settings, bump: true)
        let warning = try #require(report.warning(node))
        #expect(warning.hasPrefix("The rebuilt surface is up to "))
        #expect(warning.hasSuffix(" mm from the original, more than the 0.0001 mm tolerance."))
    }

    @Test func limitsAreSentences() async throws {
        let (degree, _, degreeNode) = try await rebuild(["degreeU": .integer(12)])
        #expect(degree.error(degreeNode) == "The degree must be from 1 to 11.")
        let (closed, _, closedNode) = try await rebuild(["spansU": .integer(0)])
        #expect(closed.error(closedNode) == "There must be at least 1 span.")
        let source = RebuildSurfaceNode.inputs
        #expect(source.first { $0.name == "degreeU" }?.range == 1...11)
        #expect(source.first { $0.name == "spansV" }?.range == 1...1000)
    }

    @Test func rebuildCurveJoinsPieces() async throws {
        let series = registry.makeNode(SeriesNode.typeID)
        var seriesNode = series
        seriesNode.inputValues["step"] = .number(10)
        seriesNode.inputValues["count"] = .integer(5)
        var vector = registry.makeNode(VectorNode.typeID)
        vector.inputValues["y"] = .number(0)
        let through = registry.makeNode(CurveThroughPointsNode.typeID)
        var node = registry.makeNode(RebuildCurveNode.typeID)
        node.inputValues["tolerance"] = .number(1000)
        let links = [
            Link(from: Endpoint(node: seriesNode.id, socket: "values"), to: Endpoint(node: vector.id, socket: "x")),
            Link(from: Endpoint(node: vector.id, socket: "vector"), to: Endpoint(node: through.id, socket: "points")),
            Link(from: Endpoint(node: through.id, socket: "curve"), to: Endpoint(node: node.id, socket: "curve")),
        ]
        let nodes = [seriesNode.id: seriesNode, vector.id: vector, through.id: through, node.id: node]
        let report = try await Evaluator(registry: registry, kernel: kernel)
            .evaluate(Graph(nodes: nodes, links: links), demand: [node.id], images: ImageResolver())
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        let curve = try #require(report.value(node, "curve")?.curves?.first)
        #expect(curve.pieceCount == 1)
        let facts = try #require(report.results[node.id]?.facts)
        #expect(facts.prefix(2) == [PayloadFact("Degree", "3"), PayloadFact("Control points", "11")])
        #expect(facts.contains { $0.label == "Deviation" })
    }

    @Test func aRebuildFeedsEditSurface() async throws {
        let source = registry.makeNode(RebuildSourceNode.typeID)
        var rebuilt = registry.makeNode(RebuildSurfaceNode.typeID)
        rebuilt.inputValues["tolerance"] = .number(1000)
        var edit = registry.makeNode(EditSurfaceNode.typeID)
        edit.inputValues[NodeSetting.poleMoves] = .poleMoves([PoleMove(index: PoleIndex(i: 2, j: 3), offset: Vector3(0, 0, 4))])
        let links = [
            Link(from: Endpoint(node: source.id, socket: "surface"), to: Endpoint(node: rebuilt.id, socket: "surface")),
            Link(from: Endpoint(node: rebuilt.id, socket: "surface"), to: Endpoint(node: edit.id, socket: "surface")),
        ]
        let nodes = [source.id: source, rebuilt.id: rebuilt, edit.id: edit]
        let report = try await Evaluator(registry: registry, kernel: kernel)
            .evaluate(Graph(nodes: nodes, links: links), demand: [edit.id], images: ImageResolver())
        #expect(report.isOK(edit), "\(String(describing: report.state(edit)))")
        let before = try #require(report.value(rebuilt, "surface")?.solids?.first)
        let after = try #require(report.value(edit, "surface")?.solids?.first)
        let (a, b) = (try await kernel.controlNet(of: before).surface, try await kernel.controlNet(of: after).surface)
        let index = 2 * a.vCount + 3
        #expect((b.poles[index] - a.poles[index] - Vector3(0, 0, 4)).length < 1e-9)
    }
}
#endif

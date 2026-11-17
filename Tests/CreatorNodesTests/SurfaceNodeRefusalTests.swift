import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// A profile with a hole, for the tests that need one (the built-in profile nodes make none).
private enum HoledProfileNode: NodeDefinition {
    static let typeID = "test.holedProfile"
    static let displayName = "Holed Profile"
    static let category = NodeCategory.profile
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("profile", .profile)]

    static func square(_ side: Double, at origin: Vector2 = .zero) -> [Segment2D] {
        let p = [origin, origin + Vector2(side, 0), origin + Vector2(side, side), origin + Vector2(0, side)]
        return (0..<4).map { .line(p[$0], p[($0 + 1) % 4]) }
    }

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["profile": .profile(Profile2D(plane: .xy, outer: square(10), holes: [square(2, at: Vector2(4, 4))]))])
    }
}

/// The surface nodes' own refusals, and the kernel's unsupported sentence from a kernel that has no surfaces.
struct SurfaceNodeRefusalTests {
    static let registry = NodeRegistry(BuiltInNodes.all + [HoledProfileNode.self])

    func run(_ nodes: [Node], _ links: [Link], demand: Node) async throws -> EvaluationReport {
        var table: [NodeID: Node] = [:]
        for node in nodes { table[node.id] = node }
        return try await Evaluator(registry: Self.registry, kernel: FakeKernel())
            .evaluate(Graph(nodes: table, links: links), demand: [demand.id], images: ImageResolver())
    }

    func make(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:]) -> Node {
        var node = Self.registry.makeNode(definition.typeID)
        node.inputValues.merge(values) { _, given in given }
        return node
    }

    func link(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) -> Link {
        Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))
    }

    @Test func aLoftSectionWithHolesIsRefusedInWords() async throws {
        let holed = make(HoledProfileNode.self), loft = make(LoftSurfaceNode.self)
        let report = try await run([holed, loft], [link(holed, "profile", loft, "sections")], demand: loft)
        #expect(report.error(loft) == "Section 1 has holes; a loft section is one loop.")
    }

    @Test func aProfileWithoutHolesIsAcceptedOnLoftSectionsAndReachesTheKernel() async throws {
        let rectangle = make(RectangleNode.self), loft = make(LoftSurfaceNode.self)
        let report = try await run([rectangle, loft], [link(rectangle, "profile", loft, "sections")], demand: loft)
        #expect(report.error(loft) == "Lofting surfaces isn't supported by this kernel yet.")
    }

    @Test func aSweepPathThatIsAListIsRefused() async throws {
        let holed = make(HoledProfileNode.self), toCurves = make(ProfileToCurvesNode.self), sweep = make(SweepNode.self)
        let report = try await run([holed, toCurves, sweep], [
            link(holed, "profile", toCurves, "profile"), link(toCurves, "curves", sweep, "path"),
            link(toCurves, "curves", sweep, "profiles"),
        ], demand: sweep)
        #expect(report.error(sweep) == "Sweep needs exactly one path.")
    }

    @Test func aSinglePointIsRefused() async throws {
        var node = make(CurveThroughPointsNode.self)
        node.inputValues["points"] = .vector(.zero)
        let report = try await run([node], [], demand: node)
        #expect(report.error(node) == "A curve needs at least two points.")
    }

    /// A list of rectangles of distinct widths on one wire, from a Series.
    func widths(_ count: Int) -> (series: Node, rectangle: Node) {
        (make(SeriesNode.self, ["start": .number(1), "count": .integer(count)]), make(RectangleNode.self))
    }

    @Test func tooManyLoftSectionsAreRefused() async throws {
        let (series, rectangle) = widths(1_001)
        let loft = make(LoftSurfaceNode.self)
        let report = try await run([series, rectangle, loft], [
            link(series, "values", rectangle, "width"),
                                                               link(rectangle, "profile", loft, "sections"),
        ], demand: loft)
        #expect(report.error(loft) == "A loft takes at most 1,000 sections.")
    }

    @Test func tooManySweepProfilesAreRefusedBeforeThePath() async throws {
        let (series, rectangle) = widths(101)
        let sweep = make(SweepNode.self), path = make(RectangleNode.self)
        let report = try await run([series, rectangle, sweep, path], [
            link(series, "values", rectangle, "width"), link(rectangle, "profile", sweep, "profiles"),
            link(path, "profile", sweep, "path"),
        ], demand: sweep)
        #expect(report.error(sweep) == "A sweep takes at most 100 profiles.")
    }

    @Test func tooManyPointsAreRefused() async throws {
        // A Series is limited to 10,000 itself, so two of them are merged.
        let first = make(SeriesNode.self, ["count": .integer(5_000)]), second = make(SeriesNode.self, ["count": .integer(5_001)])
        let merge = make(MergeNode.self), vector = make(VectorNode.self), curve = make(CurveThroughPointsNode.self)
        let report = try await run([first, second, merge, vector, curve], [
            link(first, "values", merge, "a"), link(second, "values", merge, "b"), link(merge, "list", vector, "x"),
            link(vector, "vector", curve, "points"),
        ], demand: curve)
        #expect(report.error(curve) == "Curve through Points takes at most 10,000 points.")
    }

    @Test func curveNodesWithoutAKernelSaySo() async throws {
        let series = make(SeriesNode.self, ["count": .integer(3)]), vector = make(VectorNode.self)
        let curve = make(CurveThroughPointsNode.self)
        var report = try await run([series, vector, curve], [link(series, "values", vector, "x"),
                                                             link(vector, "vector", curve, "points"),
        ], demand: curve)
        #expect(report.error(curve) == "Interpolated curves isn't supported by this kernel yet.")
        let rectangle = make(RectangleNode.self), extrude = make(ExtrudeNode.self)
        let edges = make(AllEdgesNode.self), fromEdges = make(CurveFromEdgesNode.self)
        report = try await run([rectangle, extrude, edges, fromEdges], [
            link(rectangle, "profile", extrude, "profile"), link(extrude, "solid", edges, "solid"),
            link(edges, "edges", fromEdges, "edges"),
        ], demand: fromEdges)
        #expect(report.error(fromEdges) == "Curves from edges isn't supported by this kernel yet.")
    }

    @Test(arguments: [
        (ExtrudeCurveNode.typeID, "Extruding a curve isn't supported by this kernel yet."),
        (RevolveCurveNode.typeID, "Revolving a curve isn't supported by this kernel yet."),
        (PlanarSurfaceNode.typeID, "Planar surfaces isn't supported by this kernel yet."),
        (SweepNode.typeID, "Sweeping isn't supported by this kernel yet."),
    ])
    func everySurfaceNodeSaysTheKernelCannotNotCrashes(typeID: String, message: String) async throws {
        let rectangle = make(RectangleNode.self)
        let node = Self.registry.makeNode(typeID)
        var links: [Link] = []
        for spec in Self.registry.inputs(for: node) where spec.type == .curve || spec.type == .profile {
            links.append(link(rectangle, "profile", node, spec.name))
        }
        let report = try await run([rectangle, node], links, demand: node)
        #expect(report.error(node) == message)
    }
}

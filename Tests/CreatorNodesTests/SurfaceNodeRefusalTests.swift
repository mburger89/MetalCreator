import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// A profile with a hole, for the tests that need one (the built-in profile nodes make none).
enum HoledProfileNode: NodeDefinition {
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

import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

/// A profile with a hole, for the refusal tests (the built-in profile nodes make none).
private enum HoledProfileNode: NodeDefinition {
    static let typeID = "test.networkHoledProfile"
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

/// NS-2 Task 3: the Network Surface node.
struct NetworkSurfaceNodeTests {
    /// A straight curve from two points: a Vector over a two-point Series on one axis.
    func line(_ h: inout Harness, axis: SocketName, fixed: [SocketName: Double]) -> Node {
        let series = h.add(SeriesNode.self, ["step": .number(10), "count": .integer(2)])
        let vector = h.add(VectorNode.self, Dictionary(uniqueKeysWithValues: fixed.map { ($0.key, ConstantValue.number($0.value)) }))
        h.wire(series, "values", to: vector, axis)
        let curve = h.add(CurveThroughPointsNode.self)
        h.wire(vector, "vector", to: curve, "points")
        return curve
    }

    func grid(_ h: inout Harness) -> Node {
        let node = h.add(NetworkSurfaceNode.self)
        let sockets: [SocketName] = ["a", "b", "c"]
        let us = h.add(MergeNode.self), vs = h.add(MergeNode.self)
        for (index, value) in [0.0, 5, 10].enumerated() {
            h.wire(line(&h, axis: "x", fixed: ["y": value]), "curve", to: us, sockets[index])
            h.wire(line(&h, axis: "y", fixed: ["x": value]), "curve", to: vs, sockets[index])
        }
        h.wire(us, "list", to: node, "u curves")
        h.wire(vs, "list", to: node, "v curves")
        return node
    }

    @Test func theNodeIsInTheSurfaceLibraryUnderMake() {
        #expect(NetworkSurfaceNode.category == .surface && NetworkSurfaceNode.librarySubgroup == "Make")
        let tolerance = NetworkSurfaceNode.inputs.first { $0.name == "tolerance" }
        #expect(tolerance?.defaultValue == .number(0.01))
        #expect(tolerance?.range == 0.0001...1)
        #expect(tolerance?.unit == .millimetres)
    }

    @Test func tooManyCurvesAreRefusedBeforeAnyKernelWork() async throws {
        var h = Harness()
        let u = h.add(SeriesNode.self, ["start": .number(1), "count": .integer(1_001)])
        let v = h.add(SeriesNode.self, ["start": .number(1), "count": .integer(1_000)])
        let ur = h.add(RectangleNode.self), vr = h.add(RectangleNode.self)
        h.wire(u, "values", to: ur, "width")
        h.wire(v, "values", to: vr, "width")
        let node = h.add(NetworkSurfaceNode.self)
        h.wire(ur, "profile", to: node, "u curves")
        h.wire(vr, "profile", to: node, "v curves")
        let report = try await h.run([node])
        #expect(report.error(node) == "A network takes at most 2,000 curves.")
    }

    func refusal(holedInU: Bool, secondInput: Bool) async throws -> String? {
        let registry = NodeRegistry(BuiltInNodes.all + [HoledProfileNode.self])
        var nodes: [Node] = [], links: [Link] = []
        let target = registry.makeNode(NetworkSurfaceNode.typeID)
        let holed = registry.makeNode(HoledProfileNode.typeID), plain = registry.makeNode(RectangleNode.typeID)
        let merge = registry.makeNode(MergeNode.typeID)
        func link(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) {
            links.append(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input)))
        }
        let holedSocket: SocketName = holedInU ? "u curves" : "v curves", other: SocketName = holedInU ? "v curves" : "u curves"
        nodes = [target, holed, plain, merge]
        link(plain, "profile", target, other)
        if secondInput {
            link(plain, "profile", merge, "a")
            link(holed, "profile", merge, "b")
            link(merge, "list", target, holedSocket)
        } else {
            link(holed, "profile", target, holedSocket)
        }
        var table: [NodeID: Node] = [:]
        for node in nodes { table[node.id] = node }
        let report = try await Evaluator(registry: registry, kernel: FakeKernel())
            .evaluate(Graph(nodes: table, links: links), demand: [target.id], images: ImageResolver())
        return report.error(target)
    }

    @Test func aHoledUCurveIsNumberedWithinTheUInput() async throws {
        #expect(try await refusal(holedInU: true, secondInput: true) == "U curve 2 has holes; a network curve is one loop.")
    }

    @Test func aHoledVCurveIsNumberedWithinTheVInput() async throws {
        #expect(try await refusal(holedInU: false, secondInput: false) == "V curve 1 has holes; a network curve is one loop.")
    }

    @Test func aKernelWithoutNetworkSurfacesSaysSo() async throws {
        var h = Harness()
        let node = h.add(NetworkSurfaceNode.self)
        let a = h.add(RectangleNode.self), b = h.add(RectangleNode.self)
        h.wire(a, "profile", to: node, "u curves")
        h.wire(b, "profile", to: node, "v curves")
        let report = try await h.run([node])
        #expect(report.error(node) == "Network surfaces isn't supported by this kernel yet.")
    }

    #if canImport(CreatorOCCT)
    @Test func aLineGridMakesASheetOfTheGridsArea() async throws {
        var h = Harness()
        let node = grid(&h)
        let kernel = OCCTKernel()
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) == nil)
        let sheet = try onlySolid(report, node, "surface")
        let area = try await kernel.properties(of: sheet).surfaceArea
        #expect(isClose(area, 100, relative: 1e-5))
    }
    #endif
}

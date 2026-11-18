import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

/// A profile with a hole (the built-in profile nodes make none).
private enum HoledProfileNode: NodeDefinition {
    static let typeID = "test.patchHoledProfile"
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

/// NS-2 Task 6: the Boundary Patch node.
struct BoundaryPatchNodeTests {
    @Test func theNodeIsInTheSurfaceLibraryUnderMake() {
        #expect(BoundaryPatchNode.category == .surface && BoundaryPatchNode.librarySubgroup == "Make")
        let continuity = BoundaryPatchNode.inputs.first { $0.name == "continuity" }
        #expect(continuity?.defaultValue == .integer(1))
        #expect(BoundaryPatchNode.inputs.filter(\.isOptional).count == 4)
    }

    @Test func nothingWiredSaysWhatToWire() async throws {
        var h = Harness()
        let node = h.add(BoundaryPatchNode.self)
        let report = try await h.run([node])
        #expect(report.error(node) == "Wire the curves or edges that bound the patch.")
    }

    @Test func aProfileWithHolesIsRefusedInWords() async throws {
        let registry = NodeRegistry(BuiltInNodes.all + [HoledProfileNode.self])
        let source = registry.makeNode(HoledProfileNode.typeID), node = registry.makeNode(BoundaryPatchNode.typeID)
        let link = Link(from: Endpoint(node: source.id, socket: "profile"), to: Endpoint(node: node.id, socket: "curves"))
        let report = try await Evaluator(registry: registry, kernel: FakeKernel())
            .evaluate(Graph(nodes: [source.id: source, node.id: node], links: [link]), demand: [node.id], images: ImageResolver())
        #expect(report.error(node) == "Profile 1 has holes; a patch boundary is one loop.")
    }

    @Test func moreThanAThousandPointsAreRefused() async throws {
        var h = Harness()
        let rect = h.add(RectangleNode.self)
        let series = h.add(SeriesNode.self, ["step": .number(1), "count": .integer(1_001)])
        let vector = h.add(VectorNode.self)
        h.wire(series, "values", to: vector, "x")
        let node = h.add(BoundaryPatchNode.self)
        h.wire(rect, "profile", to: node, "curves")
        h.wire(vector, "vector", to: node, "points")
        let report = try await h.run([node])
        #expect(report.error(node) == "A patch takes at most 1,000 points.")
    }

    @Test func theFakeKernelSaysPatchesAreUnsupported() async throws {
        var h = Harness()
        let rect = h.add(RectangleNode.self)
        let node = h.add(BoundaryPatchNode.self)
        h.wire(rect, "profile", to: node, "curves")
        let report = try await h.run([node])
        #expect(report.error(node) == "Boundary patches isn't supported by this kernel yet.")
    }
}

#if canImport(CreatorOCCT)
struct BoundaryPatchNodeOCCTTests {
    let kernel = OCCTKernel()

    func solid(_ report: EvaluationReport, _ node: Node) throws -> Solid {
        try #require(report.value(node, "surface")?.solids?.first)
    }

    @Test func aSquareOfFourLinesHasAnAreaOfOneHundred() async throws {
        var h = Harness()
        let rect = h.add(RectangleNode.self, ["width": .number(10), "height": .number(10)])
        let node = h.add(BoundaryPatchNode.self, ["continuity": .integer(0)])
        h.wire(rect, "profile", to: node, "curves")
        let report = try await h.run([node], kernel: kernel)
        let sheet = try #require(report.value(node, "surface")?.solids?.first, "\(String(describing: report.error(node)))")
        #expect(report.isOK(node))
        #expect(isClose(try await kernel.properties(of: sheet).surfaceArea, 100, relative: 1e-6))
    }

    @Test func anEmptyEdgeSetIsLikeAnUnwiredOne() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let byTag = h.add(EdgesByTagNode.self)
        h.wire(box, "solid", to: byTag, "solid")
        let node = h.add(BoundaryPatchNode.self)
        h.wire(byTag, "edges", to: node, "edges")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) == "Wire the curves or edges that bound the patch.")
    }

    @Test func aKernelWarningBecomesTheNodesWarning() async throws {
        var h = Harness()
        let rect = h.add(RectangleNode.self)
        let node = h.add(BoundaryPatchNode.self)
        h.wire(rect, "profile", to: node, "curves")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.warning(node) == "No bounding edge is a sheet's open edge, so the patch is only G0.")
    }

    @Test func pickedEdgesOfALoftedBellsOpenTopBuildAPatchAtG1() async throws {
        var h = Harness()
        let merge = h.add(MergeNode.self)
        for (index, (z, diameter)) in [(0.0, 10.0), (5, 9), (10, 6)].enumerated() {
            let circle = h.add(CircleNode.self, ["diameter": .number(diameter), "plane": .plane(.through(Vector3(0, 0, z)))])
            h.wire(circle, "profile", to: merge, ["a", "b", "c"][index])
        }
        let loft = h.add(LoftSurfaceNode.self)
        h.wire(merge, "list", to: loft, "sections")
        let byTag = h.add(EdgesByTagNode.self)
        h.wire(loft, "surface", to: byTag, "solid")
        let first = try await h.run([loft], kernel: kernel)
        let sheet = try solid(first, loft)
        let top = sheet.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.end) } }.map(\.id)
        h.set(byTag, NodeSetting.picks, .edgePicks(sheet.topology.picks(for: top)))
        let node = h.add(BoundaryPatchNode.self)
        h.wire(byTag, "edges", to: node, "edges")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) == nil, "\(String(describing: report.error(node))) \(report.results.mapValues(\.state))")
        let patch = try solid(report, node)
        #expect(patch.topology.faces.count == 1)
        #expect(try await kernel.properties(of: patch).surfaceArea > 28)
    }
}
#endif

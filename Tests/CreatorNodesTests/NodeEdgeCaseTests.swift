import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// Inputs the node tests didn't reach (final review, M3 ledger): limits, refusals and graph shapes at the edge of what a
/// node accepts, each pinned as the nodes behave now.
struct NodeEdgeCaseTests {
    @Test func aGridLargerThanTheLimitIsExplainedEvenWhenEachCountIsWithin() async throws {
        var h = Harness()
        // 200 × 100 = 20,000 points: each count is allowed, the product is not.
        let grid = h.add(GridPointsNode.self, ["countX": .integer(200), "countY": .integer(100)])
        let report = try await h.run([grid])
        #expect(report.error(grid) == "The grid can have at most 10,000 points.")
    }

    @Test func aNegativeCornerRadiusIsExplained() async throws {
        var h = Harness()
        let rounded = h.add(RoundedRectangleNode.self, ["cornerRadius": .number(-1)])
        let report = try await h.run([rounded])
        #expect(report.error(rounded) == "“cornerRadius” can't be negative.")
    }

    @Test func aZeroAxisIsRefusedEvenWhenTheAngleIsZero() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let transform = h.add(TransformNode.self, ["angle": .number(0), "axisDirection": .vector(.zero)])
        h.wire(box, "solid", to: transform, "solid")
        let report = try await h.run([transform])
        #expect(report.error(transform) == "The rotation axis direction can't be zero.")
    }

    /// A 10 × 10 × 10 box on XY (centre (0, 0, 5)), turned 90° about the vertical line through (10, 0), then moved (1, 2, 3):
    /// the centre goes (0, 0) → (10, −10) by the turn, then to (11, −8, 8).
    @Test func rotationAboutAnOffOriginAxisIsFollowedByTheMove() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let transform = h.add(TransformNode.self, [
            "move": .vector(Vector3(1, 2, 3)), "angle": .number(90),
            "axisOrigin": .vector(Vector3(10, 0, 0)), "axisDirection": .vector(.unitZ),
        ])
        h.wire(box, "solid", to: transform, "solid")
        let solid = try onlySolid(try await h.run([transform], kernel: OCCTKernel()), transform)
        #expect(isClose(solid.bounds.center, Vector3(11, -8, 8), tolerance: 1e-6))
        #expect(isClose(solid.bounds.size, Vector3(10, 10, 10), tolerance: 1e-6))
    }

    @Test func aSmoothLoftThroughThreeCirclesIsASolid() async throws {
        var h = Harness()
        let diameters = h.add(SeriesNode.self, ["start": .number(20), "step": .number(-6), "count": .integer(3)])
        let heights = h.add(SeriesNode.self, ["start": .number(0), "step": .number(10), "count": .integer(3)])
        let plane = h.add(PlaneNode.self)
        h.wire(heights, "values", to: plane, "offset")
        let circles = h.add(CircleNode.self)
        h.wire(diameters, "values", to: circles, "diameter")
        h.wire(plane, "plane", to: circles, "plane")
        let loft = h.add(LoftNode.self, ["ruled": .bool(false)])
        h.wire(circles, "profile", to: loft, "sections")
        let kernel = OCCTKernel()
        let solid = try onlySolid(try await h.run([loft], kernel: kernel), loft)
        let smooth = try await volume(solid, kernel)
        // Between the cylinder of the smallest section (r 4) and of the largest (r 10) over the same 20 mm.
        #expect(smooth > Double.pi * 16 * 20 && smooth < Double.pi * 100 * 20)
        #expect(isClose(solid.bounds.size.z, 20, relative: 1e-4))
    }

    @Test func anOutputOfAnEmptyListWarnsThereIsNothingToExport() async throws {
        var h = Harness()
        let none = h.add(GridPointsNode.self, ["countX": .integer(0), "countY": .integer(1), "total": .integer(0)])
        let box = h.box(10, 10, 10)
        let copies = h.add(TransformNode.self)
        h.wire(box, "solid", to: copies, "solid")
        h.wire(none, "points", to: copies, "move")
        let output = h.add(OutputNode.self, output: true)
        h.wire(copies, "solid", to: output, "solid")
        let report = try await h.run([output])
        #expect(report.warning(output) == "There is nothing to preview or export.")
    }

    // MARK: Called directly, with inputs no wire produces

    func context(_ definition: any NodeDefinition.Type) -> EvalContext {
        EvalContext(node: BuiltInNodes.registry.makeNode(definition.typeID), item: 0, parameters: [:])
    }

    @Test func aClosingPointEqualToTheFirstIsDroppedFromAClosedPolyline() async throws {
        let corners = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 10, 0), Vector3(0, 0, 0)]
        let inputs = NodeInputs(item: 0, slots: [
            "points": .list(corners.map(Scalar.vector)), "closed": .item(.bool(true)), "plane": .item(.plane(.xy)),
        ])
        let outputs = try await PolylineNode.evaluate(inputs, kernel: FakeKernel(), context: context(PolylineNode.self))
        guard case .profile(let profile)? = outputs.values["profile"] else {
            Issue.record("no profile: \(outputs)")
            return
        }
        #expect(profile.outer.count == 3, "three corners, closed by the third segment, not four")
        #expect(profile.isClosed)
    }

    @Test func edgeSetsOfEqualButSeparateSolidsCombine() async throws {
        let kernel = FakeKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let profile = Profile2D.rectangle(width: 10, height: 10, plane: .xy)
        let first = try await kernel.extrude(profile, distance: 5, mode: .oneSided, tag: tag)
        let second = try await kernel.extrude(profile, distance: 5, mode: .oneSided, tag: tag)
        #expect(first !== second, "two instances, as when the cache evicts one rule's solid and keeps the other")
        let edges = first.topology.edges.map(\.id)
        let inputs = NodeInputs(item: 0, slots: [
            "a": .item(.edgeSet(EdgeSet(solid: first, edges: Array(edges.prefix(2))))),
            "b": .item(.edgeSet(EdgeSet(solid: second, edges: Array(edges.dropFirst(1).prefix(2))))),
            "operation": .item(.integer(2)),
        ])
        let outputs = try await EdgeSetOpNode.evaluate(inputs, kernel: kernel, context: context(EdgeSetOpNode.self))
        guard case .edgeSet(let combined)? = outputs.values["edges"] else {
            Issue.record("no edge set: \(outputs)")
            return
        }
        #expect(combined.edges == [edges[1]], "the intersection of the two overlapping pairs")
    }
}

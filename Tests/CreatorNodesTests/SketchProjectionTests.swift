import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import CreatorSketch
import Testing

/// Sketcher spec §7, projecting model edges into a sketch.
struct SketchProjectionTests {
    func edge(_ kind: CurveKind, _ curve: EdgeCurve?) -> EdgeInfo {
        EdgeInfo(id: EdgeID(0), kind: kind, direction: nil, length: 1, midpoint: .zero, convexity: .convex,
                 faces: [FaceID(0), FaceID(1)], curve: curve)
    }

    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 }

    // MARK: - The projection itself

    @Test func aLineProjectsAlongThePlaneNormal() {
        let line = edge(.line, .line(start: Vector3(0, 3, 5), end: Vector3(10, 4, 7)))
        #expect(EdgeProjection.project(line, onto: .xy) == .curve(.line(Vector2(0, 3), Vector2(10, 4))))
        #expect(EdgeProjection.project(line, onto: .xz) == .curve(.line(Vector2(0, 5), Vector2(10, 7))))
    }

    @Test func aLinePerpendicularToThePlaneIsRefused() {
        let upright = edge(.line, .line(start: Vector3(1, 1, 0), end: Vector3(1, 1, 9)))
        #expect(EdgeProjection.project(upright, onto: .xy) == .refused(EdgeProjection.toPoint))
    }

    @Test func aCircleFacingThePlaneBecomesACircle() {
        let rim = edge(.circle, .circle(center: Vector3(1, 2, 4), axis: -.unitZ, radius: 3, start: Vector3(4, 2, 4),
                                        sweep: 2 * .pi))
        #expect(EdgeProjection.project(rim, onto: .xy) == .curve(.circle(center: Vector2(1, 2), radius: 3)))
    }

    @Test func anArcComesOutCounterClockwiseInThePlaneWhicheverWayItsAxisPoints() {
        let up = edge(.circle, .circle(center: .zero, axis: .unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: .pi / 2))
        guard case .curve(.arc(_, _, let start, let end)) = EdgeProjection.project(up, onto: .xy) else {
            Issue.record("expected an arc")
            return
        }
        #expect(near(start.radians, 0) && near(end.radians, .pi / 2))
        // About −Z the same start sweeps clockwise in the plane, to −90°.
        let down = edge(.circle, .circle(center: .zero, axis: -.unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: .pi / 2))
        guard case .curve(.arc(_, _, let downStart, let downEnd)) = EdgeProjection.project(down, onto: .xy) else {
            Issue.record("expected an arc")
            return
        }
        #expect(near(downStart.radians, -.pi / 2) && near(downEnd.radians, 0))
    }

    @Test func anObliqueCircleOrAnUnsupportedCurveIsRefused() {
        let tilted = edge(.circle, .circle(center: .zero, axis: .unitX, radius: 2, start: Vector3(0, 2, 0), sweep: 2 * .pi))
        #expect(EdgeProjection.project(tilted, onto: .xy) == .refused(EdgeProjection.oblique))
        #expect(EdgeProjection.project(edge(.bspline, nil), onto: .xy) == .refused(EdgeProjection.unsupported))
    }

    // MARK: - Through the Sketch node

    /// A 20 × 10 × 6 box wired into a Sketch's `references`. The sketch holds projection `p1` of the
    /// box edge between `first` and `second` (by role) and a reference length `d1` on it.
    struct Projected {
        var h = Harness()
        let box: Node
        let sketch: Node

        init(width: Double = 20) {
            box = h.box(width, 10, 6)
            var drawing = Sketch()
            let projected = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1",
                                                                                 curve: .line(.zero, Vector2(1, 0))))))
            drawing.addDimension(.length(projected), value: 1, isDriving: false)
            sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
            h.wire(box, "solid", to: sketch, "references")
        }

        mutating func pick(between first: TopoRole, and second: TopoRole, kernel: any Kernel = FakeKernel()) async throws {
            let solid = try onlySolid(try await h.run([box], kernel: kernel), box)
            let tags = [TopoTag(node: box.id, item: 0, role: first), TopoTag(node: box.id, item: 0, role: second)]
            let edge = try #require(solid.topology.edges.first { edge in
                guard let key = solid.topology.key(of: edge) else { return false }
                return key.first.union(key.second) == Set(tags)
            })
            h.set(sketch, NodeSetting.projection("p1"), .edgePicks(solid.topology.picks(for: [edge.id])))
        }
    }

    @Test func aProjectedEdgeTakesItsPickedEdgesShape() async throws {
        var projected = Projected(width: 20)
        try await projected.pick(between: .endCap, and: .side(segment: 0))
        let report = try await projected.h.run([projected.sketch])
        // Open on its own, so the sketch warns, but the edge is resolved and measured.
        #expect(report.warning(projected.sketch) == "1 curve doesn't form a closed region.")
        #expect(report.value(projected.sketch, "measurements")?.numbers.map { $0.map { $0.rounded() } } == [20])
    }

    @Test func aProjectedEdgeFollowsAnUpstreamChange() async throws {
        var projected = Projected(width: 20)
        try await projected.pick(between: .endCap, and: .side(segment: 0))
        projected.h.set(projected.box, "distance", .number(6))
        let rectangle = try #require(projected.h.graph.incomingLink(to: Endpoint(node: projected.box.id, socket: "profile")))
        projected.h.set(try #require(projected.h.graph.nodes[rectangle.from.node]), "width", .number(35))
        let report = try await projected.h.run([projected.sketch])
        #expect(report.value(projected.sketch, "measurements")?.numbers.map { $0.map { $0.rounded() } } == [35])
    }

    @Test func aMissingPickOrReferenceSuspendsTheEdgeWithAWarning() async throws {
        var projected = Projected()
        var report = try await projected.h.run([projected.sketch])
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1 has no picked edge." + SketchProjections.ignored) == true)
        // Its reference length would read the placeholder curve stored in the sketch (1 mm), so it isn't output.
        #expect(report.warning(projected.sketch)?.contains(SketchSolve.unmeasured("d1", because: SketchSolve.onSuspendedEdge)) == true)
        #expect(report.value(projected.sketch, "measurements")?.numbers == [])
        try await projected.pick(between: .endCap, and: .side(segment: 0))
        projected.h.set(projected.sketch, NodeSetting.projection("p1"),
                        .edgePicks([EdgePick(key: EdgeKey([TopoTag(node: NodeID(), item: 0, role: .endCap)], []), matchCount: 1)]))
        report = try await projected.h.run([projected.sketch])
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1 matches no edge of the references."
            + SketchProjections.ignored) == true)
    }

    @Test func noReferenceSolidIsExplained() async throws {
        var projected = Projected()
        try await projected.pick(between: .endCap, and: .side(segment: 0))
        let link = try #require(projected.h.graph.incomingLink(to: Endpoint(node: projected.sketch.id, socket: "references")))
        var graph = projected.h.graph
        graph.links.removeAll { $0 == link }
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(graph, demand: [projected.sketch.id])
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1 has no reference solid: wire the solid it was "
            + "picked on into “references”." + SketchProjections.ignored) == true)
    }

    @Test func anEdgeThatProjectsToAPointIsSuspendedWithAWarning() async throws {
        var projected = Projected()
        try await projected.pick(between: .side(segment: 0), and: .side(segment: 1))
        let report = try await projected.h.run([projected.sketch])
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1 can't be projected: \(EdgeProjection.toPoint)."
            + SketchProjections.ignored) == true)
    }

    @Test func aConstraintOnASuspendedEdgeIsIgnoredNotAConflict() async throws {
        var projected = Projected()
        var drawing = Sketch()
        let edge = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .line(.zero, Vector2(1, 0))))))
        let point = drawing.addPoint(Vector2(3, 3))
        drawing.add(.fix(point, at: Vector2(3, 3)))
        drawing.add(.pointOn(point: point, curve: edge))
        projected.h.set(projected.sketch, NodeSetting.sketch, .sketch(drawing))
        let report = try await projected.h.run([projected.sketch])
        #expect(report.error(projected.sketch) == nil)
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1 has no picked edge.") == true)
    }

    @Test func aPickWhoseMatchCountDriftedSaysSo() async throws {
        var projected = Projected()
        try await projected.pick(between: .endCap, and: .side(segment: 0))
        guard case .edgePicks(var picks)? = projected.h.graph.nodes[projected.sketch.id]?.inputValues[NodeSetting.projection("p1")] else {
            Issue.record("no pick stored")
            return
        }
        picks[0].matchCount = 2
        projected.h.set(projected.sketch, NodeSetting.projection("p1"), .edgePicks(picks))
        let report = try await projected.h.run([projected.sketch])
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1's pick changed. Matched 1 edge, expected 2.") == true)
        #expect(EdgeTagMatch.drift([(1, 2)]) == "Matched 1 edge, expected 2.")
    }

    // MARK: - On OCCT (sketcher spec §10, Integration)

    @Test func aProjectedEdgeSurvivesAnUpstreamWidthChangeOnOCCT() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let box = h.box(20, 10, 6)
        // Three sides of a rectangle; the fourth (y = −depth / 2) is the box's projected top-front edge.
        var drawing = Sketch()
        let edge = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .line(.zero, Vector2(1, 0))))))
        let a = drawing.addPoint(Vector2(-10, -4)), b = drawing.addPoint(Vector2(10, -4))
        let c = drawing.addPoint(Vector2(10, 5)), d = drawing.addPoint(Vector2(-10, 5))
        let right = drawing.addLine(from: b, to: c)
        drawing.addLine(from: c, to: d)
        let left = drawing.addLine(from: d, to: a)
        drawing.add(.fix(c, at: Vector2(10, 5)))
        drawing.add(.fix(d, at: Vector2(-10, 5)))
        drawing.add(.vertical(left))
        drawing.add(.vertical(right))
        drawing.add(.pointOn(point: a, curve: edge))
        drawing.add(.pointOn(point: b, curve: edge))
        drawing.addDimension(.length(edge), value: 1, isDriving: false)
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        h.wire(box, "solid", to: sketch, "references")
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(2)])
        h.wire(sketch, "profiles", to: extrude, "profile")

        let solid = try onlySolid(try await h.run([box], kernel: kernel), box)
        let tags: Set = [TopoTag(node: box.id, item: 0, role: .endCap), TopoTag(node: box.id, item: 0, role: .side(segment: 0))]
        let picked = try #require(solid.topology.edges.first { edge in
            solid.topology.key(of: edge).map { $0.first.union($0.second) == tags } ?? false
        })
        h.set(sketch, NodeSetting.projection("p1"), .edgePicks(solid.topology.picks(for: [picked.id])))

        // Widening the box lengthens the edge, so its measurement follows. Deepening it moves the edge to
        // y = −depth / 2, so the sketch's bottom side follows it and the region grows.
        for (boxWidth, depth) in [(20.0, 10.0), (30, 14)] {
            let link = try #require(h.graph.incomingLink(to: Endpoint(node: box.id, socket: "profile")))
            let rectangle = try #require(h.graph.nodes[link.from.node])
            h.set(rectangle, "width", .number(boxWidth))
            h.set(rectangle, "height", .number(depth))
            let report = try await h.run([extrude], kernel: kernel)
            #expect(report.isOK(sketch), "\(String(describing: report.state(sketch)))")
            #expect(report.value(sketch, "measurements")?.numbers.map { $0.map { $0.rounded() } } == [boxWidth])
            #expect(isClose(try await volume(try onlySolid(report, extrude), kernel), 2 * 20 * (5 + depth / 2)))
        }
    }

    /// The edge of `solid` between the faces tagged `first` and `second` by `node`.
    func edge(of solid: Solid, _ node: Node, between first: TopoRole, and second: TopoRole) throws -> EdgeInfo {
        let tags: Set = [TopoTag(node: node.id, item: 0, role: first), TopoTag(node: node.id, item: 0, role: second)]
        return try #require(solid.topology.edges.first { edge in
            solid.topology.key(of: edge).map { $0.first.union($0.second) == tags } ?? false
        })
    }

    /// A Ø6 cylinder on (4, −3), picked at either rim (OCCT may run one of them about −Z): the rim
    /// projects to its circle, which bounds a region and is measured by a reference radius.
    @Test(arguments: [TopoRole.startCap, .endCap])
    func aCylinderRimProjectsToItsCircleOnOCCT(_ rim: TopoRole) async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(6), "plane": .plane(.through(Vector3(4, -3, 0)))])
        let cylinder = h.add(ExtrudeNode.self, ["distance": .number(5)])
        h.wire(circle, "profile", to: cylinder, "profile")
        var drawing = Sketch()
        let projected = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .line(.zero, Vector2(1, 0))))))
        drawing.addDimension(.radius(projected), value: 1, isDriving: false)
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        h.wire(cylinder, "solid", to: sketch, "references")
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(2)])
        h.wire(sketch, "profiles", to: extrude, "profile")
        let solid = try onlySolid(try await h.run([cylinder], kernel: kernel), cylinder)
        let picked = try edge(of: solid, cylinder, between: rim, and: .side(segment: 0))
        h.set(sketch, NodeSetting.projection("p1"), .edgePicks(solid.topology.picks(for: [picked.id])))

        let report = try await h.run([extrude], kernel: kernel)
        #expect(report.isOK(sketch), "\(String(describing: report.state(sketch)))")
        let measured = try #require(report.value(sketch, "measurements")?.numbers)
        #expect(measured.count == 1 && isClose(measured[0], 3))
        let outline = try #require(report.value(sketch, "profiles")?.profiles?.first).outer
        guard outline.count == 1, case .arc(let center, let radius, _, _)? = outline.first else {
            Issue.record("expected one circle, got \(outline)")
            return
        }
        #expect((center - Vector2(4, -3)).length < 1e-9 && isClose(radius, 3))
        #expect(isClose(try await volume(try onlySolid(report, extrude), kernel), 2 * 9 * Double.pi))
    }

    /// A 20 × 10 plate's R2 corner arc about (8, −3) in world XY, picked at either rim, closed into a
    /// quarter disc by two fixed lines through its centre, on a sketch plane facing up (+Z) or down (−Z,
    /// where the arc's axis points against the normal and the plane's y is world −Y). The region extrudes
    /// to the quarter disc only if the arc came out counter-clockwise in the plane between the lines' ends.
    @Test(arguments: [TopoRole.startCap, .endCap], [false, true])
    func aCornerArcProjectsCounterClockwiseFromEitherRimOnOCCT(_ rim: TopoRole, facingDown: Bool) async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let outline = h.add(RoundedRectangleNode.self, ["width": .number(20), "height": .number(10), "cornerRadius": .number(2)])
        let plate = h.add(ExtrudeNode.self, ["distance": .number(3)])
        h.wire(outline, "profile", to: plate, "profile")
        var drawing = Sketch(plane: .fixed(facingDown ? Plane(origin: .zero, normal: -.unitZ, xAxis: .unitX) : .xy))
        let arc = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .line(.zero, Vector2(1, 0))))))
        let y = facingDown ? -1.0 : 1
        let corners = [Vector2(10, -3 * y), Vector2(8, -3 * y), Vector2(8, -5 * y)]
        let points = corners.map { drawing.addPoint($0) }
        for (point, at) in zip(points, corners) { drawing.add(.fix(point, at: at)) }
        drawing.addLine(from: points[0], to: points[1])
        drawing.addLine(from: points[1], to: points[2])
        drawing.addDimension(.radius(arc), value: 1, isDriving: false)
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        h.wire(plate, "solid", to: sketch, "references")
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(2)])
        h.wire(sketch, "profiles", to: extrude, "profile")
        let solid = try onlySolid(try await h.run([plate], kernel: kernel), plate)
        let picked = try edge(of: solid, plate, between: rim, and: .side(segment: 1))
        h.set(sketch, NodeSetting.projection("p1"), .edgePicks(solid.topology.picks(for: [picked.id])))

        let report = try await h.run([extrude], kernel: kernel)
        #expect(report.isOK(sketch), "\(String(describing: report.state(sketch)))")
        #expect(report.value(sketch, "measurements")?.numbers.map { $0.map { $0.rounded() } } == [2])
        #expect(isClose(try await volume(try onlySolid(report, extrude), kernel), 2 * Double.pi))
    }
}

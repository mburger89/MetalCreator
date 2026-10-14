import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// Cull by Region (patterns spec §4): placements kept inside or outside a profile, or within or beyond a distance from a
/// point, an edge set or a face. Culling keeps paths.
struct CullByRegionNodeTests {
    /// A row of five placements on the X axis, 10 mm apart: x = −20, −10, 0, 10, 20 (indices 0 to 4), into a Cull by Region.
    struct Fixture {
        var h = Harness()
        let cull: Node
        let placements: Node

        init(_ settings: [SocketName: ConstantValue] = [:]) {
            let grid = h.add(GridPointsNode.self, ["countX": .integer(5), "countY": .integer(1)])
            placements = h.add(PointsToPlacementsNode.self)
            cull = h.add(CullByRegionNode.self, settings)
            h.wire(grid, "points", to: placements, "points")
            h.wire(placements, "placements", to: cull, "placements")
        }

        mutating func profile(width: Double, height: Double = 10, plane: Plane = .xy) {
            let rectangle = h.add(RectangleNode.self, ["width": .number(width), "height": .number(height), "plane": .plane(plane)])
            h.wire(rectangle, "profile", to: cull, "profile")
        }

        mutating func point(_ x: Double, _ y: Double = 0, _ z: Double = 0) {
            let vector = h.add(VectorNode.self, ["x": .number(x), "y": .number(y), "z": .number(z)])
            h.wire(vector, "vector", to: cull, "point")
        }

        func kept(_ kernel: any Kernel = FakeKernel()) async throws -> [Int] {
            let report = try await h.run([cull], kernel: kernel)
            if let message = report.error(cull) { throw NodeError.invalidValue(message) }
            return report.positions(cull, "placements")?.first ?? []
        }

        func message(_ kernel: any Kernel = FakeKernel()) async throws -> String? {
            let report = try await h.run([cull], kernel: kernel)
            return report.error(cull)
        }
    }

    // MARK: profile

    @Test func placementsInsideAProfileAreKept() async throws {
        var f = Fixture([:])
        f.profile(width: 25)
        #expect(try await f.kept() == [1, 2, 3])
    }

    @Test func placementsOutsideAProfileAreKept() async throws {
        var f = Fixture(["keep": .integer(1)])
        f.profile(width: 25)
        #expect(try await f.kept() == [0, 4])
    }

    @Test func aPlacementOnTheOutlineIsInside() async throws {
        var f = Fixture([:])
        f.profile(width: 20)
        #expect(try await f.kept() == [1, 2, 3], "x = ±10 lie on the outline")
    }

    @Test func theProfileIsAPrismSoHeightAboveItsPlaneDoesNotMatter() async throws {
        var f = Fixture([:])
        f.profile(width: 25, plane: .through(Vector3(0, 0, 50)))
        #expect(try await f.kept() == [1, 2, 3])
    }

    @Test func aProfileOnAnotherPlaneIsReadInItsOwnCoordinates() async throws {
        var f = Fixture([:])
        // Plane x = 0 facing +X: its local x is world Y and local y world Z, so a row along X all projects onto its origin.
        f.profile(width: 4, height: 4, plane: Plane(origin: .zero, normal: .unitX, xAxis: .unitY))
        #expect(try await f.kept() == [0, 1, 2, 3, 4])
    }

    @Test func theProfileIsRequiredForTheProfileReference() async throws {
        let f = Fixture([:])
        #expect(try await f.message() == "Connect or set “profile”.")
    }

    // MARK: point

    @Test func placementsWithinADistanceOfAPointAreKept() async throws {
        var f = Fixture(["reference": .integer(1), "distance": .number(12)])
        f.point(0, 0, 0)
        #expect(try await f.kept() == [1, 2, 3])
    }

    @Test func placementsBeyondADistanceOfAPointAreKept() async throws {
        var f = Fixture(["reference": .integer(1), "keep": .integer(1), "distance": .number(12)])
        f.point(0, 0, 0)
        #expect(try await f.kept() == [0, 4])
    }

    @Test func aPlacementAtExactlyTheDistanceIsWithin() async throws {
        var f = Fixture(["reference": .integer(1), "distance": .number(10)])
        f.point(0, 0, 0)
        #expect(try await f.kept() == [1, 2, 3])
    }

    @Test func distanceIsMeasuredInThreeDimensions() async throws {
        var f = Fixture(["reference": .integer(1), "distance": .number(10)])
        f.point(0, 0, 8)
        #expect(try await f.kept() == [2], "only x = 0 is within 10 of (0, 0, 8): √(10² + 8²) is 12.8")
    }

    @Test func aNegativeDistanceIsRefused() async throws {
        var f = Fixture(["reference": .integer(1), "distance": .number(-1)])
        f.point(0)
        #expect(try await f.message() == "“distance” can't be negative.")
    }

    #if canImport(CreatorOCCT)
    // MARK: edges

    /// A 20 × 20 × 10 box on z = 0…10 (OCCT, for its exact edges), its edges wired into `edges`.
    func boxEdges(_ f: inout Fixture) {
        let box = f.h.box(20, 20, 10)
        let edges = f.h.add(AllEdgesNode.self)
        f.h.wire(box, "solid", to: edges, "solid")
        f.h.wire(edges, "edges", to: f.cull, "edges")
    }

    @Test func placementsWithinADistanceOfAnEdgeSetAreKept() async throws {
        var f = Fixture(["reference": .integer(2), "distance": .number(1)])
        boxEdges(&f)
        // The bottom edges at x = ±10 pass through the placements at x = ±10; the others are 10 away.
        #expect(try await f.kept(OCCTKernel()) == [1, 3])
    }

    @Test func placementsBeyondADistanceOfAnEdgeSetAreKept() async throws {
        var f = Fixture(["reference": .integer(2), "keep": .integer(1), "distance": .number(1)])
        boxEdges(&f)
        #expect(try await f.kept(OCCTKernel()) == [0, 2, 4])
    }
    #endif

    @Test func edgesOfNoExactShapeAreRefusedWithTheCount() async throws {
        let spline = EdgeInfo(id: EdgeID(0), kind: .bspline, direction: nil, length: 5, midpoint: .zero, convexity: .convex, faces: [])
        let line = EdgeInfo(id: EdgeID(1), kind: .line, direction: .unitX, length: 5, midpoint: .zero, convexity: .convex, faces: [],
                            curve: .line(start: .zero, end: Vector3(5, 0, 0)))
        let base = try await FakeKernel().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided,
                                                  tag: NodeTag(node: NodeID(), item: 0))
        let solid = Solid(topology: Topology(faces: [], edges: [spline, line]), bounds: base.bounds, storage: base.storage)
        let expected = "Cull by Region measures from straight and circular edges: 1 of the 2 selected edges are another kind of curve."
        #expect(throws: NodeError.invalidValue(expected)) {
            _ = try RegionDistance.nearestEdge(EdgeSet(solid: solid, edges: [EdgeID(0), EdgeID(1)]))
        }
    }

    @Test func aStraightEdgeIsMeasuredAsASegmentNotALine() {
        let edge = EdgeCurve.line(start: .zero, end: Vector3(10, 0, 0))
        #expect(isClose(RegionDistance.distance(from: Vector3(5, 3, 0), to: edge), 3))
        #expect(isClose(RegionDistance.distance(from: Vector3(13, 4, 0), to: edge), 5), "past the end it is the end that counts")
        #expect(isClose(RegionDistance.distance(from: Vector3(-3, -4, 0), to: edge), 5))
    }

    @Test func anArcIsMeasuredToItsEndsBeyondItsSweep() {
        // A quarter circle of radius 10 about the Z axis from +X to +Y.
        let arc = EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 10, start: Vector3(10, 0, 0), sweep: .pi / 2)
        #expect(isClose(RegionDistance.distance(from: Vector3(7.071067811865476, 7.071067811865476, 0), to: arc), 0), "on the arc")
        #expect(isClose(RegionDistance.distance(from: Vector3(14.142135623730951, 14.142135623730951, 0), to: arc), 10))
        #expect(isClose(RegionDistance.distance(from: Vector3(10, -4, 0), to: arc), 4), "below the start: the start counts")
        #expect(isClose(RegionDistance.distance(from: Vector3(-3, 10, 0), to: arc), 3), "past the end: the end counts")
    }

    #if canImport(CreatorOCCT)
    @Test func aCircularEdgeIsMeasuredToTheCircleNotTheCentre() async throws {
        // A circle of radius 10 on z = 0: the placements at x = ±10 are on it, the one at 0 is 10 from it, ±20 are 10 outside.
        let kernel = OCCTKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let disc = try await kernel.extrude(.circle(radius: 10, center: .zero, plane: .xy), distance: 5, mode: .oneSided, tag: tag)
        let rim = disc.topology.edges.filter { $0.kind == .circle && !$0.isSeam && abs($0.midpoint.z) < 1e-6 }.map(\.id)
        let nearest = try RegionDistance.nearestEdge(EdgeSet(solid: disc, edges: rim))
        #expect(isClose(nearest(Vector3(10, 0, 0)), 0))
        #expect(isClose(nearest(Vector3(0, 0, 0)), 10))
        #expect(isClose(nearest(Vector3(20, 0, 0)), 10))
        #expect(isClose(nearest(Vector3(10, 0, 3)), 3))
        #expect(isClose(nearest(Vector3(0, 7, 0)), 3))
    }

    // MARK: faces

    @Test func distanceToAFlatFaceIsDistanceToItsPlane() async throws {
        let kernel = OCCTKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let box = try await kernel.extrude(.rectangle(width: 20, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        let top = try #require(box.topology.faces.first { $0.kind == .plane && ($0.normal?.z ?? 0) > 0.5 })
        let nearest = try RegionDistance.nearestFace(FaceSet(solid: box, faces: [top.id]))
        #expect(isClose(nearest(Vector3(100, 100, 10)), 0), "far beside the face, on its plane")
        #expect(isClose(nearest(Vector3(0, 0, 4)), 6))
        #expect(isClose(nearest(Vector3(0, 0, 13)), 3), "above it counts the same")
    }

    @Test func aCurvedFaceIsRefusedWithTheCount() async throws {
        let kernel = OCCTKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let can = try await kernel.extrude(.circle(radius: 5, center: .zero, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        let wall = try #require(can.topology.faces.first { $0.kind == .cylinder })
        #expect(throws: NodeError.invalidValue("Cull by Region measures from flat faces for now: 1 of the 1 selected face is curved.")) {
            _ = try RegionDistance.nearestFace(FaceSet(solid: can, faces: [wall.id]))
        }
    }

    @Test func theFaceReferenceCullsByDistanceToTheFacePlane() async throws {
        let kernel = OCCTKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let box = try await kernel.extrude(.rectangle(width: 40, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        let top = try #require(box.topology.faces.first { $0.kind == .plane && ($0.normal?.z ?? 0) > 0.5 })
        let placements = DataTree.list([-20, -10, 0, 10, 20].map { .plane(.through(Vector3(Double($0), 0, 4))) })
        let node = BuiltInNodes.registry.makeNode(CullByRegionNode.typeID)
        let inputs = NodeInputs(item: 0, slots: [
            "placements": .tree(placements), "reference": .item(.integer(3)), "keep": .item(.integer(0)),
            "distance": .item(.number(7)), "faces": .item(.faceSet(FaceSet(solid: box, faces: [top.id]))),
        ])
        let context = EvalContext(node: node, item: 0, parameters: [:])
        let outputs = try await CullByRegionNode.evaluate(inputs, kernel: kernel, context: context)
        #expect(try #require(outputs.trees["placements"]).itemCount == 5, "all are 6 mm below the top face, within 7")
    }
    #endif

    // MARK: shape

    @Test func aTreeOfPlacementsKeepsItsBranchesAndPaths() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(2), "centred": .bool(false)])
        let placements = h.add(PointsToPlacementsNode.self)
        let rows = h.add(PartitionNode.self, ["size": .integer(3)])
        let cull = h.add(CullByRegionNode.self, ["reference": .integer(1), "keep": .integer(1), "distance": .number(5)])
        let origin = h.add(VectorNode.self)
        h.wire(grid, "points", to: placements, "points")
        h.wire(placements, "placements", to: rows, "tree")
        h.wire(rows, "tree", to: cull, "placements")
        h.wire(origin, "vector", to: cull, "point")
        let report = try await h.run([cull])
        // Points (0,0) (10,0) (20,0) / (0,10) (10,10) (20,10): beyond 5 mm of the origin leaves all but {0;0}.
        #expect(report.positions(cull, "placements") == [[1, 2], [0, 1, 2]])
        #expect(report.tree(cull, "placements")?.depth == 2)
    }
}

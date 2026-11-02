import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 2e of G-b: a corner where three fillet strips end is one degree-17 three-sided Bezier patch, G2 to all three
/// strips (g2_corners); a corner the patch is not accepted for is a counted G1 refill.
struct G2FilletCornerTests {
    let base = G2FilletTests()
    let history = G2FilletHistoryTests()
    let validity = G2FilletCornerValidityTests()

    func report(_ built: G2FilletTests.Built, _ name: String) {
        let r = built.report
        print("G2CORNER \(name): corners \(r.corners) g2 \(r.g2_corners) g1 \(r.g1_corners) tried \(r.corner_attempts)"
            + " ms \(r.corner_milliseconds) mismatch \(r.corner_block_mismatch) minLambda \(r.corner_min_lambda)"
            + " maxCurvature \(r.corner_max_curvature) minSine \(r.corner_min_sine)")
    }

    @Test func aBoxCornerIsG2() throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        let mids: [[Double]] = [[10, 0, 10], [0, 10, 10], [0, 0, 5]]
        let built = try base.build(box, midpoints: mids, radius: 2)
        report(built, "box corner")
        let seams = base.cornerGaps(built.report)
        #expect(built.report.corners == 1)
        #expect(built.report.g2_corners == 1)
        #expect(built.report.g1_corners == 0)
        #expect(seams.count == 3)
        for seam in seams {
            print("G2CORNER seam: position \(seam.position) angle \(seam.angle_degrees) ratio \(seam.curvature_ratio)")
            #expect(seam.position <= 1e-4)
            #expect(seam.angle_degrees <= 0.01)
            #expect(seam.curvature_ratio <= 1)
        }
        // The patch is regular and gentle: curvature within 4 / r (the circular corner's is 1 / r), a positive across scale.
        #expect(built.report.corner_max_curvature <= 4.0 / 2)
        #expect(built.report.corner_min_lambda > 0)
        #expect(built.report.corner_block_mismatch <= 1e-6)
        #expect(built.report.corner_min_sine > 0.05)
        base.expectSpringsG2(built, seams: 6)
        // The history names the same faces as the circular fillet's (the patch is the last face of the solid).
        try history.expectSameHistory(box, midpoints: mids, radius: 2)
    }

    /// All 12 edges of a box: eight corners, each a patch. Release timing: `swift test -c release --filter G2Corner`.
    @Test func allEightBoxCornersAreG2() throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        var mids: [[Double]] = []
        for y in [0.0, 20] { for z in [0.0, 10] { mids.append([10, y, z]) } }
        for x in [0.0, 20] { for z in [0.0, 10] { mids.append([x, 10, z]) } }
        for x in [0.0, 20] { for y in [0.0, 20] { mids.append([x, y, 5]) } }
        let clock = ContinuousClock()
        let edges = try OCCTKernel.serialized { try base.helper.topology(of: box) }
        let ids = try mids.map { try base.helper.edge(edges, near: $0) }
        // Timed inside the lock, so waiting for another test's OCCT work is not counted.
        let (built, elapsed) = try OCCTKernel.serialized {
            var made: G2FilletTests.Built?
            let time = try clock.measure { made = try box.blendedCurvatureContinuous(edges: ids, size: 2, weight: 1) }
            return (made, time)
        }
        let result = try #require(built)
        report(result, "all 12 edges")
        print("G2CORNER all 12 edges: total \(elapsed), corners \(result.report.corner_milliseconds) ms")
        #expect(result.report.strips == 12)
        #expect(result.report.corners == 8)
        #expect(result.report.g2_corners == 8)
        #expect(result.report.g1_corners == 0)
        let seams = base.cornerGaps(result.report)
        #expect(seams.count == 24)
        for seam in seams {
            #expect(seam.position <= 1e-4)
            #expect(seam.angle_degrees <= 0.01)
            #expect(seam.curvature_ratio <= 1)
        }
        #expect(OCCTKernel.serialized { result.shape.validity } == .valid)
        try history.expectSameHistory(box, midpoints: mids, radius: 2)
    }

    /// A corner whose springs meet at an angle other than 90 degrees: the strips' sides are mitred (each leaves the hole's
    /// corner along the other strip's spring) and the corner is one G2 patch, seams measured on the final solid.
    func expectNonOrthogonalCornerIsG2(_ shape: OCCTShape, midpoints: [[Double]], name: String,
                                       sourceLocation: SourceLocation = #_sourceLocation) throws {
        let built = try base.build(shape, midpoints: midpoints, radius: 1)
        report(built, name)
        #expect(OCCTKernel.serialized { built.shape.validity } == .valid, sourceLocation: sourceLocation)
        #expect(built.report.corners == 1, sourceLocation: sourceLocation)
        #expect(built.report.g2_corners == 1, sourceLocation: sourceLocation)
        #expect(built.report.g1_corners == 0, sourceLocation: sourceLocation)
        let seams = base.cornerGaps(built.report)
        #expect(seams.count == 3, sourceLocation: sourceLocation)
        for seam in seams {
            print("G2CORNER \(name) seam: position \(seam.position) angle \(seam.angle_degrees) ratio \(seam.curvature_ratio)")
            #expect(seam.position <= 1e-4, sourceLocation: sourceLocation)
            #expect(seam.angle_degrees <= 0.01, sourceLocation: sourceLocation)
            #expect(seam.curvature_ratio <= 1, sourceLocation: sourceLocation)
        }
        #expect(built.report.corner_max_curvature <= 4.0, sourceLocation: sourceLocation)
        #expect(built.report.corner_min_lambda > 0, sourceLocation: sourceLocation)
        #expect(built.report.corner_block_mismatch <= 1e-6, sourceLocation: sourceLocation)
        #expect(built.report.corner_min_sine > 0.05, sourceLocation: sourceLocation)
        base.expectSpringsG2(built, seams: 6, sourceLocation: sourceLocation)
        try history.expectSameHistory(shape, midpoints: midpoints, radius: 1)
    }

    /// The top corner of a hexagonal prism: the springs on the top meet at 120 degrees (the strips are cut back).
    @Test func aHexagonalPrismCornerIsG2() throws {
        let points = validity.hexagon()
        try expectNonOrthogonalCornerIsG2(try validity.polygonPrism(points), midpoints: validity.topCorner(points, at: 0, height: 10),
                                          name: "hexagon")
    }

    /// The top corner of a triangular prism: the springs meet at 60 degrees (the strips are carried on into the hole).
    @Test func aTriangularPrismCornerIsG2() throws {
        let points = validity.triangle()
        try expectNonOrthogonalCornerIsG2(try validity.polygonPrism(points), midpoints: validity.topCorner(points, at: 0, height: 10),
                                          name: "triangle")
    }

    /// A drafted prism's top corner: two of the hole's corners lie on drafted walls, 79 degrees apart.
    @Test func aDraftedPrismCornerIsG2() throws {
        try expectNonOrthogonalCornerIsG2(try validity.coverage.draftedPrism(), midpoints: [[0, -8, 10], [-8, 0, 10], [-9, -9, 5]],
                                          name: "drafted")
    }

    /// Through the kernel: the hexagonal prism's corner is not tangent only, so the Fillet node warns of nothing.
    @Test func aHexagonalPrismCornerIsNotTangentOnly() async throws {
        let kernel = OCCTKernel()
        let points = validity.hexagon()
        let segments = points.indices.map { Segment2D.line(points[$0], points[($0 + 1) % points.count]) }
        let solid = try await kernel.extrude(Profile2D(plane: .xy, segments: segments), distance: 10, mode: .oneSided, tag: newTag())
        let mids = validity.topCorner(points, at: 0, height: 10)
        let edges = try mids.map { mid in
            try #require(solid.topology.edges.min { a, b in
                distance(a.midpoint, mid) < distance(b.midpoint, mid)
            }).id
        }
        let made = try await kernel.fillet(solid, edges: edges, radius: 1, profile: .curvatureContinuous(weight: 1), tag: newTag())
        #expect(made.tangentOnlyCorners == 0)
        #expect(made.tangentOnlyJoins == 0)
    }

    func distance(_ point: Vector3, _ mid: [Double]) -> Double {
        let (dx, dy, dz) = (point.x - mid[0], point.y - mid[1], point.z - mid[2])
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// The apex of a square pyramid (the intersection of two crossed gable prisms), all four hip edges filleted.
    @Test func aFourFilletCornerIsCountedOrRefused() throws {
        func gable(alongX: Bool) throws -> OCCTShape {
            // A triangle 20 wide and 10 high, extruded 20.
            let triangle = [Vector2(-10, 0), Vector2(10, 0), Vector2(0, 10)]
            let segments = triangle.indices.map { Segment2D.line(triangle[$0], triangle[($0 + 1) % 3]) }
            return try OCCTKernel.serialized {
                let prism = try OCCTShape.extrude(Profile2D(plane: .xz, segments: segments), distance: 20).0
                let centred = try prism.transformed(by: Transform(translation: Vector3(0, 10, 0))).0
                guard !alongX else { return centred }
                return try centred.transformed(by: Transform(translation: .zero, rotationAxis: Axis.z, rotation: .degrees(90))).0
            }
        }
        let (first, second) = (try gable(alongX: true), try gable(alongX: false))
        let pyramid = try OCCTKernel.serialized { try OCCTShape.boolean(.intersect, first, [second]).0 }
        let edges = try OCCTKernel.serialized { try base.helper.topology(of: pyramid) }
        let hips = edges.filter { $0.mid[2] > 4 && $0.mid[2] < 6 }
        print("G2CORNER pyramid: \(edges.count) edges, hips at \(hips.map { $0.mid })")
        #expect(hips.count == 4)
        do {
            let built = try base.build(pyramid, midpoints: hips.map { $0.mid }, radius: 0.5)
            report(built, "pyramid apex")
            #expect(OCCTKernel.serialized { built.shape.validity } == .valid)
            // Four strips end at the apex: the three-sided patch does not apply, the G1 refill takes it.
            #expect(built.report.g2_corners == 0)
            #expect(built.report.g1_corners >= 1)
        } catch let error as OCCTError {
            print("G2CORNER pyramid apex: refused \(error.message)")
        }
    }
}

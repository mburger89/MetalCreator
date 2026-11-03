import COCCT
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The promise holds everywhere along a spring seam, not only where the shim's own check samples it: position 1e-4 mm,
/// angle 0.01 degrees and curvature within its allowance, read at thousands of points that include the seam's two ends.
/// Next to a kinked join the curvature used to be skipped in the last 3.3 % of the seam, and a sliver of a spring at a
/// strip's end was only a chord that the even samples stepped over: 2.3e-4 mm on the first fixture here.
struct G2FilletDenseSeamTests {
    let base = G2FilletTests()
    let cover = G2FilletCoverageTests()

    struct Fixture: Sendable, CustomTestStringConvertible {
        var sizes: [Double]
        var corner: Double
        var ruled: Bool
        var radius: Double
        var weight: Double = 1

        var testDescription: String {
            "\(ruled ? "ruled" : "smooth") \(sizes) corner \(corner), radius \(radius), weight \(weight)"
        }
    }

    /// The kinked chains that missed the promise inside a sliver before every span was sampled, then the ones with the
    /// largest curvature ratio next to a join.
    static let fixtures = [
        Fixture(sizes: [20, 17, 16], corner: 2, ruled: true, radius: 1, weight: 0.75),
        Fixture(sizes: [20, 19, 18.5], corner: 3, ruled: true, radius: 2),
        Fixture(sizes: [20, 17, 16], corner: 2, ruled: false, radius: 1.5),
        Fixture(sizes: [20, 19, 18.5], corner: 3, ruled: false, radius: 2),
        Fixture(sizes: [20, 17, 16], corner: 3, ruled: true, radius: 1),
        Fixture(sizes: [20, 17, 16], corner: 3, ruled: false, radius: 1),
        Fixture(sizes: [20, 30, 18], corner: 3, ruled: false, radius: 0.5),
    ]

    func loft(_ fixture: Fixture) throws -> OCCTShape {
        let profiles = fixture.sizes.enumerated().map { index, side in
            let plane = Plane(origin: Vector3(0, 0, 5 * Double(index)), normal: .unitZ, xAxis: .unitX)
            return Profile2D.roundedRectangle(width: side, height: side, radius: fixture.corner, plane: plane)
        }
        return try OCCTKernel.serialized { try OCCTShape.loft(profiles, ruled: fixture.ruled).0 }
    }

    /// The final solid's spring seams: the edges along the top of the loft with both ends on the top face or both off
    /// it. A join between two strips runs from the one to the other, so it is not one (its curvature is what the kink
    /// warning is about).
    func springs(of shape: OCCTShape, radius: Double) throws -> [Int] {
        var topology = occt_topology()
        var status = occt_status()
        try #require(OCCTKernel.serialized { occt_read_topology(shape.raw, &topology, &status) } == 1)
        defer { occt_topology_free(&topology) }
        return (0..<Int(topology.edge_count)).filter { i in
            let edge = topology.edges[i]
            let onTop = (abs(edge.start.2 - 10) < 1e-6, abs(edge.end.2 - 10) < 1e-6)
            let alongTheTop = abs(edge.start.2 - edge.end.2) < 1 && edge.midpoint.2 > 10 - 2 * radius - 1e-6
            return edge.has_ends != 0 && alongTheTop && onTop.0 == onTop.1
        }
    }

    @Test(arguments: fixtures)
    func everyPlaceOfEverySpringSeamKeepsThePromise(_ fixture: Fixture) throws {
        let shape = try loft(fixture)
        let midpoint = [0, -fixture.sizes[2] / 2, 10]
        let built = try base.build(shape, midpoints: [midpoint], radius: fixture.radius, weight: fixture.weight)
        #expect(built.report.g1_joins > 0, "the fixture must have kinked joins")
        let edges = try springs(of: built.shape, radius: fixture.radius)
        #expect(edges.count == Int(built.report.seams_total), "the filter found the spring seams and nothing else")
        for edge in edges {
            var seam = occt_g2_seam()
            let read = OCCTKernel.serialized { occt_edge_seam_dense(built.shape.raw, Int32(edge + 1), 4001, &seam) }
            #expect(read == 1)
            #expect(seam.position <= 1e-4, "edge \(edge): position \(seam.position)")
            #expect(seam.angle_degrees <= 0.01, "edge \(edge): angle \(seam.angle_degrees)")
            #expect(seam.curvature_ratio <= 1, "edge \(edge): curvature ratio \(seam.curvature_ratio)")
        }
    }
}

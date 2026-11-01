import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 1 of G-b: the quintic G2 sections and the strips built from them (spec §G-b Construction).
struct G2FilletSpikeTests {
    // MARK: Section

    /// {position, direction, acceleration} as the shim reads them.
    typealias End = [Double]

    func section(_ e0: End, _ len0: Double, _ e1: End, _ len1: Double, at t: Double) -> (p: [Double], d1: [Double], d2: [Double]) {
        var out = [Double](repeating: 0, count: 9)
        #expect(occt_g2_section_test(e0, len0, e1, len1, t, &out) == 1)
        return (Array(out[0..<3]), Array(out[3..<6]), Array(out[6..<9]))
    }

    func expectClose(_ a: [Double], _ b: [Double], _ tolerance: Double = 1e-9,
                     sourceLocation: SourceLocation = #_sourceLocation) {
        for i in 0..<3 {
            #expect(abs(a[i] - b[i]) <= tolerance, "\(a) vs \(b)", sourceLocation: sourceLocation)
        }
    }

    /// Checks the Hermite data at both ends: position, tangent = len * direction, second derivative = len^2 * acceleration.
    func checkEnds(_ e0: End, _ len0: Double, _ e1: End, _ len1: Double) {
        let start = section(e0, len0, e1, len1, at: 0)
        expectClose(start.p, Array(e0[0..<3]))
        expectClose(start.d1, Array(e0[3..<6]).map { $0 * len0 })
        expectClose(start.d2, Array(e0[6..<9]).map { $0 * len0 * len0 })
        let finish = section(e0, len0, e1, len1, at: 1)
        expectClose(finish.p, Array(e1[0..<3]))
        expectClose(finish.d1, Array(e1[3..<6]).map { $0 * len1 })
        expectClose(finish.d2, Array(e1[6..<9]).map { $0 * len1 * len1 })
    }

    @Test func planarToPlanarMatchesPositionTangentAndZeroCurvature() {
        // Corner at x = 0, z = 10, radius 2: from (2, 0, 10) heading -x to (0, 0, 8) heading -z.
        let e0: End = [2, 0, 10, -1, 0, 0, 0, 0, 0]
        let e1: End = [0, 0, 8, 0, 0, -1, 0, 0, 0]
        let d = occt_g2_tangent_length(2 * 2.0.squareRoot(), .pi / 2)
        checkEnds(e0, d, e1, d)
    }

    @Test func planarToCylinderMatchesTheCylindersCurvature() {
        // One end meets a cylinder of radius 5 curving towards +z (acceleration 1/5 along +z).
        let e0: End = [2, 0, 10, -1, 0, 0, 0, 0, 0]
        let e1: End = [0, 0, 8, 0, 0, -1, 0.2, 0, 0]
        checkEnds(e0, 3, e1, 3.3)
    }

    @Test func cylinderToCylinderMatchesBothCurvatures() {
        let e0: End = [2, 1, 10, -0.6, 0, -0.8, 0.1 * 0.8, 0, -0.1 * 0.6]
        let e1: End = [0, 1, 8, 0.28, 0.96, 0, -0.25 * 0.96, 0.25 * 0.28, 0]
        checkEnds(e0, 2.5, e1, 4.0)
    }

    @Test func theWeightScalesTheEndTangents() {
        let e0: End = [2, 0, 10, -1, 0, 0, 0, 0, 0]
        let e1: End = [0, 0, 8, 0, 0, -1, 0, 0, 0]
        let d = occt_g2_tangent_length(2 * 2.0.squareRoot(), .pi / 2)
        for weight in [0.5, 1.0, 2.0] {
            let start = section(e0, weight * d, e1, weight * d, at: 0)
            #expect(abs(start.d1[0] + weight * d) < 1e-9)
        }
        // The convention: 4 r tan(theta / 4), for r = 2 and a right angle.
        #expect(abs(d - 4 * 2 * tan(Double.pi / 8)) < 1e-12)
    }

    // MARK: Strips

    struct Gaps {
        var position = 0.0, angle = 0.0, curvatureRatio = 0.0, curvature = 0.0
    }

    func topology(of shape: OCCTShape) throws -> [(index: Int, mid: [Double])] {
        var topology = occt_topology()
        var status = occt_status()
        #expect(occt_read_topology(shape.raw, &topology, &status) == 1)
        defer { occt_topology_free(&topology) }
        return (0..<Int(topology.edge_count)).map { i in
            let m = topology.edges[i].midpoint
            return (i, [m.0, m.1, m.2])
        }
    }

    func edge(_ edges: [(index: Int, mid: [Double])], near point: [Double]) throws -> EdgeID {
        let found = try #require(edges.first { e in (0..<3).allSatisfy { abs(e.mid[$0] - point[$0]) < 1e-6 } })
        return EdgeID(found.index)
    }

    func gaps(_ report: occt_g2_report) -> Gaps {
        var g = Gaps()
        withUnsafeBytes(of: report.seams) { raw in
            let seams = raw.bindMemory(to: occt_g2_seam.self)
            for i in 0..<Int(report.seam_count) {
                g.position = max(g.position, seams[i].position)
                g.angle = max(g.angle, seams[i].angle_degrees)
                g.curvature = max(g.curvature, seams[i].curvature)
                g.curvatureRatio = max(g.curvatureRatio, seams[i].curvature_ratio)
            }
        }
        return g
    }

    func run(_ name: String, edgeMidpoints: [[Double]], weight: Double = 1, staysInsideTheBox: Bool = true) throws {
        let box = try OCCTShape.box(20, 20, 10)
        let edges = try OCCTKernel.serialized { try topology(of: box) }
        let ids = try edgeMidpoints.map { try edge(edges, near: $0) }
        let clock = ContinuousClock()
        typealias Built = (shape: OCCTShape, history: [OCCTHistoryRecord], report: occt_g2_report)
        func build(_ weight: Double) throws -> (Built, Duration) {
            var built: Built?
            // The mean of 20 builds; every build also measures the seams, as the kernel will on each evaluation.
            let time = try clock.measure {
                for _ in 0..<20 {
                    built = try OCCTKernel.serialized { try box.blendedCurvatureContinuous(edges: ids, size: 2, weight: weight) }
                }
            } / 20
            return (try #require(built), time)
        }
        let (g1, g1Time) = try build(0)
        let (g2, g2Time) = try build(weight)
        let g1Gaps = gaps(g1.report), g2Gaps = gaps(g2.report)
        let validity = OCCTKernel.serialized { g2.shape.validity }
        print("G2SPIKE \(name) w=\(weight): seams \(g2.report.seam_count) strips \(g2.report.strips) sections \(g2.report.sections)")
        print("G2SPIKE \(name) w=\(weight): G1 gaps \(g1Gaps) time \(g1Time)")
        print("G2SPIKE \(name) w=\(weight): G2 gaps \(g2Gaps) time \(g2Time) validity \(validity)")
        print("G2SPIKE \(name) w=\(weight): volume \(g2.shape.volume), circular \(g1.shape.volume)")
        #expect(validity == .valid)
        // The quintic strip takes a little less material than the circle's, and never more than the box holds.
        if staysInsideTheBox {
            #expect(g2.shape.volume < 4000)
            #expect(abs(g2.shape.volume - g1.shape.volume) < 20)
        } else {
            #expect(g2.shape.volume > 4000)
        }
        #expect(g2.report.seam_count == 2 * ids.count)
        #expect(g2Gaps.position <= 1e-4)
        #expect(g2Gaps.angle <= 0.01)
        #expect(g2Gaps.curvatureRatio <= 1)
    }

    @Test func oneTopEdgeOfABoxHasG2Strips() throws {
        try run("one edge", edgeMidpoints: [[10, 0, 10]])
    }

    @Test func threeEdgesAtACornerHaveG2Strips() throws {
        try run("corner", edgeMidpoints: [[10, 0, 10], [0, 10, 10], [0, 0, 5]])
    }
}

extension G2FilletSpikeTests {
    @Test func theWeightChangesTheShapeButNotTheContinuity() throws {
        for weight in [0.5, 1.4] {
            try run("one edge", edgeMidpoints: [[10, 0, 10]], weight: weight)
        }
    }

    /// Finding: with zero curvature at both ends, a right-angle corner's quintic leaves the corner's faces once
    /// the end tangents pass 2.5 * the chord (weight about 1.5), so the solid grows beyond the box. It stays valid
    /// and G2 at the seams; the weight range of the spec (up to 2) needs a cap or a different end rule.
    @Test func aWeightOfTwoOvershootsTheCornerButStaysG2AndValid() throws {
        try run("one edge", edgeMidpoints: [[10, 0, 10]], weight: 2, staysInsideTheBox: false)
    }
}

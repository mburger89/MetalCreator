#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-2 review fixes: arcs, closed curves, names by input order and the size cap.
extension NetworkSurfaceTests {
    @Test func arcsAreApproximatedAndBuild() async throws {
        // A quarter cylinder of radius 10 about the Y axis: u curves are arcs at y = 0, 5 and 10, v curves lines along y.
        var u: [Curve] = []
        for y in [0.0, 5, 10] {
            let arc = CurvePiece.arc(center: Vector3(0, y, 0), normal: Vector3(0, -1, 0), radius: 10,
                                     start: Vector3(10, y, 0), sweep: .pi / 2)
            u.append(try await kernel.makeCurve([arc], tag: tag))
        }
        var v: [Curve] = []
        for degrees in [0.0, 45, 90] {
            let angle = degrees * .pi / 180
            v.append(try await line(Vector3(10 * cos(angle), 0, 10 * sin(angle)), Vector3(10 * cos(angle), 10, 10 * sin(angle))))
        }
        let sheet = try await kernel.networkSurface(u: u, v: v, tolerance: 0.01, tag: tag)
        #expect(try await maxMiss(u + v, sheet) <= 0.01)
        let area = try await kernel.properties(of: sheet).surfaceArea
        #expect(abs(area - 5 * .pi * 10) < 0.05, "the area is \(area)")
    }

    @Test func aClosedCurveIsRefused() async throws {
        let (u, v) = try await gridLines()
        let circle = try await kernel.makeCurve([.arc(center: Vector3(5, 5, 0), normal: .unitZ, radius: 3, start: Vector3(8, 5, 0),
                                                      sweep: 2 * .pi),
        ], tag: tag)
        await #expect {
            try await kernel.networkSurface(u: [u[0], circle, u[2]], v: v, tolerance: 0.01, tag: tag)
        } throws: { message(of: $0) == "Network curves must be open; a closed curve can't be part of a network yet." }
    }

    @Test func curvesAreNamedByTheirPlaceInTheInput() async throws {
        // The lifted v curve (x = 10) is first in the list and the u curve at y = 0 is second; the sorted order is the reverse.
        let (u, v) = try await gridLines(liftedV: 2, lift: 0.5)
        await #expect {
            try await kernel.networkSurface(u: [u[2], u[0], u[1]], v: [v[2], v[0], v[1]], tolerance: 0.01, tag: tag)
        } throws: { message(of: $0) == "U curve 2 and v curve 1 miss each other by 0.5 mm." }
    }

    @Test func aCrossingTwiceIsNamedByTheInputOrderToo() async throws {
        let (u, v) = try await gridLines()
        let twice = try await parabola(Vector3(4, 0, 0), Vector3(6, 20, 0), Vector3(4, 10, 0))
        // u curves reversed in the list: y = 10 is first. v: the doubling curve is the first, x = 10 the last.
        await #expect {
            try await kernel.networkSurface(u: [u[2], u[1], u[0]], v: [twice, v[0], v[2]], tolerance: 0.01, tag: tag)
        } throws: { message(of: $0) == "U curve 1 crosses v curve 1 more than once." }
    }

    @Test func aGridTooBigIsRefusedBeforeAnyWork() async throws {
        let (u, v) = try await gridLines()
        // 317 x 317 curves are 100,489 crossings; the same three lines repeated cost nothing to make.
        let many = 317
        let us = (0..<many).map { u[$0 % 3] }
        let vs = (0..<many).map { v[$0 % 3] }
        await #expect {
            try await kernel.networkSurface(u: us, v: vs, tolerance: 0.01, tag: tag)
        } throws: { message(of: $0) == "The network is too detailed: it would need 100,489 control points (the limit is 100,000)." }
    }
}
#endif

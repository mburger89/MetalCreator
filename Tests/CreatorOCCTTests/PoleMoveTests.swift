#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-3 Task 3: moving a sheet's or a curve's control points.
struct PoleMoveTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    func spline(_ poles: [Vector3], degree: Int = 3) async throws -> Curve {
        let count = poles.count
        let interior = Array(1..<(count - degree))
        let knots = [0.0] + interior.map { Double($0) } + [Double(count - degree)]
        let mults = [degree + 1] + interior.map { _ in 1 } + [degree + 1]
        return try await kernel.makeCurve(
            [.spline(BSplineCurve3D(degree: degree, poles: poles, knots: knots, multiplicities: mults))], tag: tag)
    }

    func loftedSheet() async throws -> Solid {
        var sections: [Curve] = []
        for (z, bulge) in [(0.0, 0.0), (5, 2), (10, 0)] {
            sections.append(try await spline([Vector3(0, 0, z), Vector3(3, bulge, z), Vector3(7, -bulge, z), Vector3(10, 0, z)]))
        }
        return try await kernel.loftSurface(sections, ruled: false, closed: false, tag: tag)
    }

    /// The structure of a topology: ids, tags, adjacency and boundary names, with the geometry left out.
    func structure(_ topology: Topology) -> [String] {
        topology.faces.map { "f\($0.id.rawValue) \($0.tags.map(String.init(describing:)).sorted()) \($0.isOnOpenShell)" }
            + topology.edges.map {
                "e\($0.id.rawValue) \($0.faces.map(\.rawValue)) \($0.tags.map(String.init(describing:)).sorted())"
            }
    }

    func endpoints(of edge: Int, in solid: Solid) async throws -> (Vector3, Vector3) {
        let curves = try await kernel.curves(from: [EdgeID(edge)], of: solid, tag: tag)
        let line = try #require(curves.first?.polyline)
        return (try #require(line.first), try #require(line.last))
    }

    @Test func movingACornerMovesTheSurfaceAndItsEdges() async throws {
        let sheet = try await loftedSheet()
        let net = try await kernel.controlNet(of: sheet).surface
        let corner = net.pole(0, 0)
        let offset = Vector3(0, 0, 2)
        let moved = try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 0, j: 0), offset: offset)])
        let after = try await kernel.controlNet(of: moved).surface
        #expect((after.pole(0, 0) - (corner + offset)).length < 1e-9)
        for i in 0..<net.uCount {
            for j in 0..<net.vCount where !(i == 0 && j == 0) {
                #expect((after.pole(i, j) - net.pole(i, j)).length < 1e-9)
            }
        }
        // Each edge ending at the corner now ends at the new corner; every other end stays where it was.
        var before: [(Vector3, Vector3)] = []
        var now: [(Vector3, Vector3)] = []
        for edge in sheet.topology.edges.indices {
            before.append(try await endpoints(of: edge, in: sheet))
            now.append(try await endpoints(of: edge, in: moved))
        }
        var throughCorner = 0
        for (old, new) in zip(before, now) {
            for (a, b) in [(old.0, new.0), (old.1, new.1)] {
                if (a - corner).length < 1e-9 {
                    throughCorner += 1
                    #expect((b - (corner + offset)).length < 1e-6)
                } else {
                    #expect((a - b).length < 1e-6)
                }
            }
        }
        #expect(throughCorner == 2)
    }

    @Test func topologyIsTheInputs() async throws {
        let sheet = try await loftedSheet()
        let moved = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: 1, j: 1), offset: Vector3(0, 1, 1))])
        #expect(structure(moved.topology) == structure(sheet.topology))
        #expect(moved.topology.faces.map(\.id) == sheet.topology.faces.map(\.id))
        #expect(!sheet.topology.edges.allSatisfy { $0.tags.isEmpty })
    }

    @Test func aTrimmedFaceStaysTrimmed() async throws {
        let circle = try await kernel.makeCurve([
            .arc(center: .zero, normal: Vector3(0, 0, 1), radius: 10, start: Vector3(10, 0, 0), sweep: 2 * .pi),
        ], tag: tag)
        let sheet = try await kernel.planarSurface([circle], tag: tag)
        let net = try await kernel.controlNet(of: sheet).surface
        let moved = try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 1, j: 1), offset: Vector3(0, 0, 1))])
        #expect(moved.topology.faces.count == 1)
        #expect(moved.topology.edges.count == sheet.topology.edges.count)
        #expect(moved.topology.edges.filter { $0.faces.count == 1 }.count == 1)
        #expect(structure(moved.topology) == structure(sheet.topology))
        #expect(abs(moved.topology.faces[0].area - sheet.topology.faces[0].area) > 1e-3)
        #expect(net.poles.count == 4)
    }

    @Test func weightsAreKept() async throws {
        let line = try await kernel.makeCurve([.line(Vector3(5, 0, 0), Vector3(5, 0, 10))], tag: tag)
        let sheet = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)), angle: .degrees(90), tag: tag)
        let before = try await kernel.controlNet(of: sheet).surface
        let weights = try #require(before.weights)
        let moved = try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 1, j: 0), offset: Vector3(0, 0, 1))])
        let after = try await kernel.controlNet(of: moved).surface
        #expect(after.weights == weights)
        #expect((after.pole(1, 0) - (before.pole(1, 0) + Vector3(0, 0, 1))).length < 1e-9)
    }

    @Test func aFullRevolveStaysPeriodic() async throws {
        let line = try await kernel.makeCurve([.line(Vector3(5, 0, 0), Vector3(5, 0, 10))], tag: tag)
        let sheet = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)), angle: .degrees(360), tag: tag)
        let before = try await kernel.controlNet(of: sheet).surface
        let moved = try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 0, j: 0), offset: Vector3(0, 0, 1))])
        let after = try await kernel.controlNet(of: moved).surface
        #expect(after.isPeriodicU == before.isPeriodicU && after.isPeriodicV == before.isPeriodicV)
        #expect(structure(moved.topology) == structure(sheet.topology))
    }

    @Test func aMissingPoleIsRefused() async throws {
        let sheet = try await loftedSheet()
        await #expect(throws: KernelError.invalidInput("That control point no longer exists.")) {
            try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 40, j: 0), offset: Vector3(0, 0, 1))])
        }
    }

    /// OpenCascade's checker is lenient about folds: a corner dragged across the net, a row collapsed to a point, a pole a billion
    /// millimetres away and the whole face collapsed to a point all pass `BRepCheck_Analyzer`. What it does reject is a surface
    /// that stops being a surface, a pole pushed to a number that isn't one, and that is what the result gate is tested with.
    @Test func aFoldingMoveIsRefused() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 3, vCount: 3, degree: 1, tag: tag)
        for offset in [Vector3(.nan, 0, 0), Vector3(0, .infinity, 0)] {
            await #expect(throws: KernelError.invalidInput("Moving these control points makes an invalid surface.")) {
                try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 1, j: 1), offset: offset)])
            }
        }
        // The folded move is still a valid B-rep to OpenCascade, and the sheet it makes keeps its topology.
        let folded = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: 0, j: 0), offset: Vector3(6, 6, 0))])
        #expect(structure(folded.topology) == structure(sheet.topology))
    }

    @Test func aCurvesPoleMoves() async throws {
        let points = [Vector3(0, 0, 0), Vector3(2, 1, 0), Vector3(4, -1, 0), Vector3(6, 1, 0), Vector3(8, 0, 0)]
        let curve = try await spline(points)
        let before = try await kernel.controlNet(of: curve).curve
        let offset = Vector3(0, 0, 3)
        let moved = try await kernel.movingPoles(of: curve, by: [PoleMove(index: PoleIndex(i: 2), offset: offset)])
        let after = try await kernel.controlNet(of: moved).curve
        #expect((after.poles[2] - (before.poles[2] + offset)).length < 1e-9)
        #expect((after.startPoint - before.startPoint).length < 1e-9)
        #expect((after.endPoint - before.endPoint).length < 1e-9)
        #expect(after.knots == before.knots && after.multiplicities == before.multiplicities)
        await #expect(throws: KernelError.invalidInput("That control point no longer exists.")) {
            try await kernel.movingPoles(of: curve, by: [PoleMove(index: PoleIndex(i: 99), offset: offset)])
        }
    }

    @Test func aPeriodicCurveStaysPeriodic() async throws {
        let points = (0..<8).map { Vector3(5 * cos(Double($0) * .pi / 4), 5 * sin(Double($0) * .pi / 4), 0) }
        let curve = try await kernel.interpolate(points, degree: 3, closed: true, startTangent: nil, endTangent: nil, tag: tag)
        let before = try await kernel.controlNet(of: curve)
        let moved = try await kernel.movingPoles(of: curve, by: [PoleMove(index: PoleIndex(i: 1), offset: Vector3(0, 0, 2))])
        let after = try await kernel.controlNet(of: moved)
        #expect(after.isPeriodic && after.curve.isPeriodic)
        #expect(after.curve.poles.count == before.curve.poles.count)
        #expect((after.curve.poles[1] - (before.curve.poles[1] + Vector3(0, 0, 2))).length < 1e-9)
        #expect(moved.isClosed)
    }
}
#endif

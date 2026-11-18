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
        // The rebuilt edges lie on the new surface all along, not only at their ends, and the moved face tessellates.
        for edge in moved.topology.edges.indices {
            let curve = try #require(try await kernel.curves(from: [EdgeID(edge)], of: moved, tag: tag).first)
            let distances = try await kernel.distances(from: curve.polyline, to: .solid(moved), signed: false)
            #expect(distances.count == curve.polyline.count && curve.polyline.count > 1)
            #expect((distances.max() ?? 1) < 1e-6)
        }
        let mesh = try await kernel.tessellate(moved, tolerance: 0.05, angle: 0.5)
        #expect(!mesh.indices.isEmpty && mesh.positions.count > 3)
    }

    @Test func boundaryRolesSurviveByPosition() async throws {
        let sheet = try await loftedSheet()
        #expect(sheet.topology.edges.count == 4)
        #expect(sheet.topology.edges.allSatisfy { $0.tags.count == 1 })
        let moved = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: 1, j: 1), offset: Vector3(0, 0, 3))])
        #expect(Set(moved.topology.edges.map(\.tags)).count == 4)
        for edge in sheet.topology.edges.indices {
            #expect(moved.topology.edges[edge].tags == sheet.topology.edges[edge].tags)
            // An interior move leaves every boundary edge where it was, so edge k is still the edge at k's place.
            let before = try await endpoints(of: edge, in: sheet)
            let after = try await endpoints(of: edge, in: moved)
            #expect((before.0 - after.0).length < 1e-6 && (before.1 - after.1).length < 1e-6)
        }
    }

    @Test func untouchedStraightEdgesStayLines() async throws {
        let square = try await kernel.makeCurve([
            .line(Vector3(0, 0, 0), Vector3(10, 0, 0)), .line(Vector3(10, 0, 0), Vector3(10, 10, 0)),
            .line(Vector3(10, 10, 0), Vector3(0, 10, 0)), .line(Vector3(0, 10, 0), Vector3(0, 0, 0)),
        ], tag: tag)
        let sheet = try await kernel.planarSurface([square], tag: tag)
        let net = try await kernel.controlNet(of: sheet).surface
        #expect(sheet.topology.edges.allSatisfy { $0.kind == .line })
        // Lift the corner pole opposite the origin: the two edges that don't reach it are untouched.
        let far = (0..<net.uCount).flatMap { i in (0..<net.vCount).map { (i, $0) } }
            .first { (net.pole($0.0, $0.1) - Vector3(10, 10, 0)).length < 1e-9 }
        let index = try #require(far)
        let moved = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: index.0, j: index.1), offset: Vector3(0, 0, 4))])
        var kept = 0
        for (before, after) in zip(sheet.topology.edges, moved.topology.edges) {
            guard case .line(let a, let b)? = before.curve else { continue }
            let touches = [a, b].contains { ($0 - Vector3(10, 10, 0)).length < 1e-9 }
            if !touches {
                kept += 1
                #expect(after.kind == .line && after.curve == before.curve && after.direction == before.direction)
            }
        }
        #expect(kept == 2)
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
        #expect(before.isPeriodicU || before.isPeriodicV)
        let seams = sheet.topology.edges.filter { $0.faces.count == 2 && $0.faces[0] == $0.faces[1] }.count
        #expect(seams == 1)
        let offset = Vector3(0, 0, 1)
        let moved = try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 0, j: 0), offset: offset)])
        let after = try await kernel.controlNet(of: moved).surface
        #expect(after.isPeriodicU == before.isPeriodicU && after.isPeriodicV == before.isPeriodicV)
        #expect(after.poles.count == before.poles.count && after.isWellFormed)
        #expect((after.pole(0, 0) - (before.pole(0, 0) + offset)).length < 1e-9)
        #expect(zip(before.poles, after.poles).filter { ($0 - $1).length > 1e-9 }.count == 1)
        // The seam is still one edge closed on the one face, and the result is a valid shape that tessellates.
        #expect(moved.topology.edges.filter { $0.faces.count == 2 && $0.faces[0] == $0.faces[1] }.count == seams)
        #expect(structure(moved.topology) == structure(sheet.topology))
        let mesh = try await kernel.tessellate(moved, tolerance: 0.05, angle: 0.5)
        #expect(!mesh.indices.isEmpty)
    }

    @Test func aMissingPoleIsRefused() async throws {
        let sheet = try await loftedSheet()
        await #expect(throws: KernelError.invalidInput("That control point no longer exists.")) {
            try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 40, j: 0), offset: Vector3(0, 0, 1))])
        }
    }

}

/// The refusals, fold checks and curve moves.
extension PoleMoveTests {
    /// OpenCascade's checker is lenient about geometry (see `folds`), but it rejects a pole that isn't a number, so that is what
    /// the result gate refuses, along with a move whose sum overflows.
    @Test func aNonFiniteMoveIsRefused() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 3, vCount: 3, degree: 1, tag: tag)
        let invalid = KernelError.invalidInput("Moving these control points makes an invalid surface.")
        for offset in [Vector3(.nan, 0, 0), Vector3(0, .infinity, 0)] {
            await #expect(throws: invalid) {
                try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 1, j: 1), offset: offset)])
            }
        }
        // Each offset is finite; the second addition overflows.
        let big = Vector3(1.7e308, 0, 0)
        await #expect(throws: invalid) {
            try await kernel.movingPoles(of: sheet, by: [
                PoleMove(index: PoleIndex(i: 1, j: 1), offset: big), PoleMove(index: PoleIndex(i: 1, j: 1), offset: big),
            ])
        }
    }

    @Test func aNonFiniteCurveMoveIsRefused() async throws {
        let curve = try await spline([Vector3(0, 0, 0), Vector3(2, 1, 0), Vector3(4, -1, 0), Vector3(6, 1, 0), Vector3(8, 0, 0)])
        let invalid = KernelError.invalidInput("Moving these control points makes an invalid curve.")
        for offset in [Vector3(.nan, 0, 0), Vector3(0, .infinity, 0)] {
            await #expect(throws: invalid) {
                try await kernel.movingPoles(of: curve, by: [PoleMove(index: PoleIndex(i: 2), offset: offset)])
            }
        }
        let big = Vector3(1.7e308, 0, 0)
        await #expect(throws: invalid) {
            try await kernel.movingPoles(of: curve, by: [
                PoleMove(index: PoleIndex(i: 2), offset: big), PoleMove(index: PoleIndex(i: 2), offset: big),
            ])
        }
    }

    @Test func aFoldedNetFolds() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 3, vCount: 3, degree: 1, tag: tag)
        #expect(try await kernel.folds(sheet) == false)
        // The corner pole dragged across the net: OpenCascade still calls the B-rep valid, folds says what it is.
        let folded = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: 0, j: 0), offset: Vector3(6, 6, 0))])
        #expect(structure(folded.topology) == structure(sheet.topology))
        #expect(try await kernel.folds(folded))
    }

    @Test func aSharpCreaseIsNotAFold() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 3, vCount: 3, degree: 1, tag: tag)
        for height in [4.0, 20.0] {
            let tent = try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 1, j: 1), offset: Vector3(0, 0, height))])
            #expect(try await kernel.folds(tent) == false, "raised \(height)")
        }
    }

    @Test func aSteepBumpIsNotAFold() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 6, vCount: 6, degree: 3, tag: tag)
        let bump = try await kernel.movingPoles(of: sheet, by: [PoleMove(index: PoleIndex(i: 2, j: 3), offset: Vector3(0, 0, 20))])
        #expect(try await kernel.folds(bump) == false)
    }

    @Test func aPlainNetDoesNotFold() async throws {
        #expect(try await kernel.folds(try await loftedSheet()) == false)
        let axis = Axis(origin: .zero, direction: Vector3(0, 0, 1))
        // A cone from the axis and a disc swept from it have a degenerate edge at the axis by design.
        for end in [Vector3(5, 0, 10), Vector3(5, 0, 0)] {
            let line = try await kernel.makeCurve([.line(.zero, end)], tag: tag)
            let sheet = try await kernel.revolve(line, axis: axis, angle: .degrees(360), tag: tag)
            #expect(try await kernel.folds(sheet) == false, "from the axis to \(end)")
        }
        let wall = try await kernel.makeCurve([.line(Vector3(5, 0, 0), Vector3(5, 0, 10))], tag: tag)
        #expect(try await kernel.folds(try await kernel.revolve(wall, axis: axis, angle: .degrees(90), tag: tag)) == false)
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

    @Test func aRationalCurvesPoleMoves() async throws {
        let arc = try await kernel.makeCurve([
            .arc(center: .zero, normal: Vector3(0, 0, 1), radius: 5, start: Vector3(5, 0, 0), sweep: .pi / 2),
        ], tag: tag)
        let before = try await kernel.controlNet(of: arc).curve
        let weights = try #require(before.weights)
        let moved = try await kernel.movingPoles(of: arc, by: [PoleMove(index: PoleIndex(i: 1), offset: Vector3(0, 0, 2))])
        let after = try await kernel.controlNet(of: moved).curve
        #expect(after.weights == weights)
        #expect((after.poles[1] - (before.poles[1] + Vector3(0, 0, 2))).length < 1e-9)
        #expect((after.poles[0] - before.poles[0]).length < 1e-9 && (after.poles[2] - before.poles[2]).length < 1e-9)
    }

    @Test func anEndPoleMovesTheCurveEnd() async throws {
        let curve = try await spline([Vector3(0, 0, 0), Vector3(2, 1, 0), Vector3(4, -1, 0), Vector3(6, 1, 0), Vector3(8, 0, 0)])
        let before = try await kernel.controlNet(of: curve).curve
        let offset = Vector3(0, 2, 0)
        let moved = try await kernel.movingPoles(
            of: curve, by: [PoleMove(index: PoleIndex(i: 0), offset: offset), PoleMove(index: PoleIndex(i: 4), offset: -offset)])
        let after = try await kernel.controlNet(of: moved).curve
        #expect((after.startPoint - (before.startPoint + offset)).length < 1e-9)
        #expect((after.endPoint - (before.endPoint - offset)).length < 1e-9)
        let line = try #require(moved.polyline)
        #expect((try #require(line.first) - after.startPoint).length < 1e-6)
        #expect((try #require(line.last) - after.endPoint).length < 1e-6)
    }

    @Test func movingAClosedCurvesEndPoleOpensIt() async throws {
        let square = [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 4, 0), Vector3(0, 4, 0), Vector3(0, 0, 0)]
        let curve = try await spline(square)
        #expect(curve.isClosed)
        let net = try await kernel.controlNet(of: curve)
        #expect(!net.isPeriodic)
        let moved = try await kernel.movingPoles(of: curve, by: [PoleMove(index: PoleIndex(i: 0), offset: Vector3(0, -1, 0))])
        #expect(!moved.isClosed)
        let both = try await kernel.movingPoles(
            of: curve, by: [PoleMove(index: PoleIndex(i: 0), offset: Vector3(0, -1, 0)),
                            PoleMove(index: PoleIndex(i: 4), offset: Vector3(0, -1, 0)),
                           ])
        #expect(both.isClosed)
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

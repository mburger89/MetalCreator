#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-3 Task 4: rebuilding a sheet's one face or a curve to a chosen degree and span count.
struct RebuildTests {
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

    func wavySheet() async throws -> Solid {
        var sections: [Curve] = []
        for (z, bulge) in [(0.0, 0.0), (5, 2), (10, 0)] {
            sections.append(try await spline([Vector3(0, 0, z), Vector3(3, bulge, z), Vector3(7, -bulge, z), Vector3(10, 0, z)]))
        }
        return try await kernel.loftSurface(sections, ruled: false, closed: false, tag: tag)
    }

    func square() async throws -> Solid {
        let loop = try await kernel.makeCurve([
            .line(Vector3(0, 0, 0), Vector3(10, 0, 0)), .line(Vector3(10, 0, 0), Vector3(10, 10, 0)),
            .line(Vector3(10, 10, 0), Vector3(0, 10, 0)), .line(Vector3(0, 10, 0), Vector3(0, 0, 0)),
        ], tag: tag)
        return try await kernel.planarSurface([loop], tag: tag)
    }

    func structure(_ topology: Topology) -> [String] {
        topology.faces.map { "f\($0.id.rawValue) \($0.tags.map(String.init(describing:)).sorted()) \($0.isOnOpenShell)" }
            + topology.edges.map {
                "e\($0.id.rawValue) \($0.faces.map(\.rawValue)) \($0.tags.map(String.init(describing:)).sorted())"
            }
    }

    @Test func aPlaneRebuildsExactly() async throws {
        let sheet = try await square()
        let result = try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 3, degreeV: 3, spansU: 2, spansV: 2))
        #expect(result.deviation < 1e-9)
        let net = try await kernel.controlNet(of: result.sheet).surface
        #expect(net.uCount == 5 && net.vCount == 5 && net.degreeU == 3 && net.degreeV == 3)
        #expect(structure(result.sheet.topology) == structure(sheet.topology))
        #expect(result.sheet.topology.edges.allSatisfy { $0.kind == .line })
    }

    @Test func aRevolvedSheetRebuildsNonRational() async throws {
        let line = try await kernel.makeCurve([.line(Vector3(10, 0, 0), Vector3(10, 0, 10))], tag: tag)
        let sheet = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)), angle: .degrees(90), tag: tag)
        #expect(try await kernel.controlNet(of: sheet).surface.weights != nil)
        let result = try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 3, degreeV: 3, spansU: 8, spansV: 1))
        let net = try await kernel.controlNet(of: result.sheet).surface
        #expect(net.weights == nil)
        #expect(result.deviation < 1e-3)
        #expect(structure(result.sheet.topology) == structure(sheet.topology))
        for (before, after) in zip(sheet.topology.edges, result.sheet.topology.edges) {
            #expect(before.tags == after.tags && before.faces == after.faces)
        }
        let mesh = try await kernel.tessellate(result.sheet, tolerance: 0.05, angle: 0.5)
        #expect(!mesh.indices.isEmpty)
    }

    @Test func aTrimmedFaceKeepsItsTrim() async throws {
        let circle = try await kernel.makeCurve([
            .arc(center: .zero, normal: Vector3(0, 0, 1), radius: 10, start: Vector3(10, 0, 0), sweep: 2 * .pi),
        ], tag: tag)
        let sheet = try await kernel.planarSurface([circle], tag: tag)
        let result = try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 2, degreeV: 2, spansU: 1, spansV: 1))
        #expect(result.sheet.topology.edges.filter { $0.faces.count == 1 }.count == 1)
        #expect(result.sheet.topology.edges.map(\.tags) == sheet.topology.edges.map(\.tags))
        #expect(structure(result.sheet.topology) == structure(sheet.topology))
        #expect(abs(result.sheet.topology.faces[0].area - sheet.topology.faces[0].area) < 0.01 * sheet.topology.faces[0].area)
        #expect(result.deviation < 1e-9)
    }

    @Test func deviationIsReportedHonestly() async throws {
        let sheet = try await wavySheet()
        let result = try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 1, degreeV: 1, spansU: 1, spansV: 1))
        #expect(result.deviation > 0.1)
        // Independent: every vertex of a fine tessellation of the source lies on it, so its distance to the result is a gap.
        let mesh = try await kernel.tessellate(sheet, tolerance: 0.002, angle: 0.05)
        let points = mesh.positions.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) }
        let gaps = try await kernel.distances(from: points, to: .solid(result.sheet), signed: false)
        let measured = try #require(gaps.max())
        #expect(abs(measured - result.deviation) <= 0.01 * result.deviation, "measured \(measured), reported \(result.deviation)")
    }

    @Test func aThreePieceCurveBecomesOne() async throws {
        let curve = try await kernel.makeCurve([
            .line(Vector3(0, 0, 0), Vector3(3, 0, 0)),
            .arc(center: Vector3(3, 10, 0), normal: Vector3(0, 0, 1), radius: 10, start: Vector3(3, 0, 0), sweep: .pi / 2),
            .line(Vector3(13, 10, 0), Vector3(13, 13, 0)),
        ], tag: tag)
        #expect(curve.pieceCount == 3)
        let result = try await kernel.rebuilt(curve, as: RebuildSpec(degreeU: 3, degreeV: 1, spansU: 12, spansV: 1), tag: tag)
        #expect(result.curve.pieceCount == 1)
        #expect(result.deviation < 0.01)
        let net = try await kernel.controlNet(of: result.curve).curve
        #expect(net.poles.count == 15 && net.degree == 3)
        #expect((net.startPoint - Vector3(0, 0, 0)).length < 1e-9)
        #expect((net.endPoint - Vector3(13, 13, 0)).length < 1e-9)
    }

    @Test func aClosedCurveStaysClosed() async throws {
        let points = (0..<8).map { Vector3(5 * cos(Double($0) * .pi / 4), 5 * sin(Double($0) * .pi / 4), 0) }
        let curve = try await kernel.interpolate(points, degree: 3, closed: true, startTangent: nil, endTangent: nil, tag: tag)
        let result = try await kernel.rebuilt(curve, as: RebuildSpec(degreeU: 3, degreeV: 1, spansU: 8, spansV: 1), tag: tag)
        #expect(result.curve.isClosed)
        #expect(result.deviation < 0.05)
    }

    @Test func theLimitsAreSentences() async throws {
        let sheet = try await square()
        let curve = try await spline([Vector3(0, 0, 0), Vector3(2, 1, 0), Vector3(4, -1, 0), Vector3(6, 1, 0)])
        await #expect(throws: KernelError.invalidInput("The degree must be from 1 to 11.")) {
            try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 12, degreeV: 3, spansU: 2, spansV: 2))
        }
        await #expect(throws: KernelError.invalidInput("The degree must be from 1 to 11.")) {
            try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 3, degreeV: 0, spansU: 2, spansV: 2))
        }
        await #expect(throws: KernelError.invalidInput("The degree must be from 1 to 11.")) {
            try await kernel.rebuilt(curve, as: RebuildSpec(degreeU: 0, degreeV: 1, spansU: 2, spansV: 1), tag: tag)
        }
        await #expect(throws: KernelError.invalidInput("There must be at least 1 span.")) {
            try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 3, degreeV: 3, spansU: 0, spansV: 2))
        }
        await #expect(throws: KernelError.invalidInput("There must be at least 1 span.")) {
            try await kernel.rebuilt(curve, as: RebuildSpec(degreeU: 3, degreeV: 1, spansU: 0, spansV: 1), tag: tag)
        }
        await #expect(throws: KernelError.invalidInput("That would make 120,000 control points; a surface may have at most 100,000.")) {
            try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 1, degreeV: 1, spansU: 399, spansV: 299))
        }
    }

    @Test func aSolidAndAManyFacedSheetAreRefused() async throws {
        let box = try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        await #expect(throws: KernelError.invalidInput("Rebuild Surface takes a sheet; this is a closed solid.")) {
            try await kernel.rebuilt(box, as: RebuildSpec(degreeU: 3, degreeV: 3, spansU: 2, spansV: 2))
        }
        let corner = try await kernel.makeCurve([
            .line(Vector3(0, 0, 0), Vector3(10, 0, 0)), .line(Vector3(10, 0, 0), Vector3(10, 10, 0)),
        ], tag: tag)
        let two = try await kernel.extrude(corner, direction: Vector3(0, 0, 1), distance: 5, symmetric: false, tag: tag)
        await #expect(throws: KernelError.invalidInput("Rebuild Surface takes a sheet with one face; this one has 2. Split it first.")) {
            try await kernel.rebuilt(two, as: RebuildSpec(degreeU: 3, degreeV: 3, spansU: 2, spansV: 2))
        }
    }

    @Test func aCircleEdgeIsKeptOnAConvertedCylinder() async throws {
        let line = try await kernel.makeCurve([.line(Vector3(5, 0, 0), Vector3(5, 0, 10))], tag: tag)
        let sheet = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)), angle: .degrees(90), tag: tag)
        let circles = sheet.topology.edges.indices.filter { sheet.topology.edges[$0].kind == .circle }
        #expect(circles.count == 2)
        let net = try await kernel.controlNet(of: sheet).surface
        // The pole at the far corner of a circular edge's other end: move one that is on neither circle edge.
        let free = (0..<net.uCount).flatMap { i in (0..<net.vCount).map { (i, $0) } }
            .first { abs(net.pole($0.0, $0.1).z - 10) < 1e-9 && abs(net.pole($0.0, $0.1).y) < 1e-9 && net.pole($0.0, $0.1).x > 4 }
        let index = try #require(free)
        let moved = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: index.0, j: index.1), offset: Vector3(0, 0, 3))])
        // The bottom circle (z = 0) is untouched by a move at z = 10 and stays a circle with its curve unchanged.
        var kept = 0
        for (before, after) in zip(sheet.topology.edges, moved.topology.edges) {
            guard before.kind == .circle else { continue }
            if abs(before.midpoint.z) < 1e-9 {
                kept += 1
                #expect(after.kind == .circle && after.curve == before.curve)
            }
        }
        #expect(kept == 1)
        let mesh = try await kernel.tessellate(moved, tolerance: 0.05, angle: 0.5)
        #expect(!mesh.indices.isEmpty)
    }

    @Test func aTrimmedFaceFoldQuery() async throws {
        let circle = try await kernel.makeCurve([
            .arc(center: .zero, normal: Vector3(0, 0, 1), radius: 10, start: Vector3(10, 0, 0), sweep: 2 * .pi),
        ], tag: tag)
        let sheet = try await kernel.planarSurface([circle], tag: tag)
        #expect(try await kernel.folds(sheet) == false)
        let net = try await kernel.controlNet(of: sheet).surface
        // The pole at the middle of the net dragged far enough through the plane that the surface turns back inside the trim.
        let corner = PoleIndex(i: 0, j: 0)
        let toward = Vector3.zero - net.pole(0, 0)
        let folded = try await kernel.movingPoles(of: sheet, by: [PoleMove(index: corner, offset: toward * 3)])
        #expect(try await kernel.folds(folded))
    }

    /// A periodic source is sampled over one period and rebuilt clamped over the same range, so the seam is one edge whose two
    /// sides sit within the fit's own gap of each other.
    @Test func aFullRevolveRebuildsAsAClampedSurface() async throws {
        let line = try await kernel.makeCurve([.line(Vector3(5, 0, 0), Vector3(5, 0, 10))], tag: tag)
        let sheet = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)), angle: .degrees(360), tag: tag)
        let result = try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 3, degreeV: 1, spansU: 12, spansV: 1))
        let net = try await kernel.controlNet(of: result.sheet).surface
        #expect(!net.isPeriodicU && !net.isPeriodicV && net.weights == nil)
        #expect(result.deviation < 5e-2)
        #expect(structure(result.sheet.topology) == structure(sheet.topology))
        let mesh = try await kernel.tessellate(result.sheet, tolerance: 0.05, angle: 0.5)
        #expect(!mesh.indices.isEmpty)
    }

    @Test func aCancelledRebuildStops() async throws {
        let sheet = try await wavySheet()
        let kernel = self.kernel
        let task = Task { try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 5, degreeV: 5, spansU: 300, spansV: 300)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
#endif

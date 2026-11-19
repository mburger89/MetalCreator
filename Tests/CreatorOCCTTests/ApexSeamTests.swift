#if canImport(CreatorOCCT)
import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-3 final review I1: a move or a rebuild never opens an apex or a seam.
struct ApexSeamTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    func dome() async throws -> Solid {
        let arc = try await kernel.makeCurve([
            .arc(center: .zero, normal: .unitZ, radius: 5, start: Vector3(5, 0, 0), sweep: .pi / 2),
        ], tag: tag)
        let axis = Axis(origin: .zero, direction: Vector3(0, 1, 0))
        return try await kernel.revolve(arc, axis: axis, angle: Angle(radians: 2 * .pi), tag: tag)
    }

    func ring(z: Double, radius: Double) async throws -> Curve {
        try await kernel.makeCurve([
            .arc(center: Vector3(0, 0, z), normal: .unitZ, radius: radius, start: Vector3(radius, 0, z), sweep: 2 * .pi),
        ], tag: tag)
    }

    func closedSplineTube() async throws -> Solid {
        let poles = [Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 8, 0), Vector3(0, 8, 0), Vector3(-2, 4, 0), Vector3(0, 0, 0)]
        let degree = 3
        let interior = Array(1..<(poles.count - degree))
        let knots = [0.0] + interior.map { Double($0) } + [Double(poles.count - degree)]
        let mults = [degree + 1] + interior.map { _ in 1 } + [degree + 1]
        let spline = BSplineCurve3D(degree: degree, poles: poles, knots: knots, multiplicities: mults)
        let curve = try await kernel.makeCurve([.spline(spline)], tag: tag)
        return try await kernel.extrude(curve, direction: .unitZ, distance: 5, symmetric: false, tag: tag)
    }

    func coincident(_ net: BSplineSurface3D, row j: Int) -> Bool {
        (0..<net.uCount).allSatisfy { (net.pole($0, j) - net.pole(0, j)).length < 1e-9 }
    }

    func apexOffset(_ i: Int) -> PoleMove { PoleMove(index: PoleIndex(i: i, j: 2), offset: Vector3(0, 1, 0)) }

    @Test func draggingOneApexPoleIsRefused() async throws {
        let sheet = try await dome()
        let net = try await kernel.controlNet(of: sheet).surface
        #expect(coincident(net, row: 2))
        await #expect(throws: KernelError.invalidInput(
            "Moving these control points opens the surface at its apex; move the matching points together.")) {
            try await kernel.movingPoles(of: sheet, by: [apexOffset(0)])
        }
    }

    @Test func draggingTheWholeApexMovesIt() async throws {
        let sheet = try await dome()
        let moved = try await kernel.movingPoles(of: sheet, by: (0..<6).map(apexOffset))
        let after = try await kernel.controlNet(of: moved).surface
        #expect(coincident(after, row: 2))
        #expect(abs(after.pole(0, 2).y - 6) < 1e-9)
        let mesh = try await kernel.tessellate(moved, tolerance: 0.05, angle: 0.5)
        #expect(!mesh.indices.isEmpty)
    }

    @Test func aSeamOpeningMoveIsRefused() async throws {
        let tube = try await closedSplineTube()
        await #expect(throws: KernelError.invalidInput(
            "Moving these control points opens the surface along its seam; move the matching points together.")) {
            try await kernel.movingPoles(of: tube, by: [PoleMove(index: PoleIndex(i: 0, j: 0), offset: Vector3(0, 0, 1))])
        }
        // Both ends of the seam together keep it closed.
        let moved = try await kernel.movingPoles(of: tube, by: [0, 5].map {
            PoleMove(index: PoleIndex(i: $0, j: 0), offset: Vector3(0, 0, 1))
        })
        #expect(try await kernel.controlNet(of: moved).surface.pole(5, 0).z == 6)
    }

    @Test func aDomeRebuildKeepsItsApex() async throws {
        let sheet = try await dome()
        let rebuilt = try await kernel.rebuilt(sheet, as: RebuildSpec(degreeU: 3, degreeV: 3, spansU: 8, spansV: 4)).sheet
        let net = try await kernel.controlNet(of: rebuilt).surface
        let apexRow = (0..<net.vCount).first { coincident(net, row: $0) && $0 > 0 } ?? -1
        #expect(apexRow == net.vCount - 1, "the collapsed row is still one point")
        #expect((net.pole(0, net.vCount - 1) - Vector3(0, 5, 0)).length < 1e-9)
        let mesh = try await kernel.tessellate(rebuilt, tolerance: 0.05, angle: 0.5)
        #expect(!mesh.indices.isEmpty)
    }

    // MARK: One tolerance, per-edge guard, centroid pin (NS-4 Task 1)

    func rowSpread(_ net: BSplineSurface3D, row j: Int) -> Double {
        let points = (0..<net.uCount).map { net.pole($0, j) }
        let centroid = points.reduce(Vector3.zero, +) * (1 / Double(points.count))
        return points.map { ($0 - centroid).length }.max() ?? 0
    }

    @Test func theToleranceIsShared() {
        #expect(occt_net_coincidence() == SurfaceNet.coincidence)
        #expect(SurfaceNet.coincidence == 1e-6)
    }

    @Test func aWideApexIsStillGuarded() async throws {
        let wide = try await kernel.spreadingApex(of: try await dome(), by: 1e-4)
        await #expect(throws: KernelError.invalidInput(
            "Moving these control points opens the surface at its apex; move the matching points together.")) {
            try await kernel.movingPoles(of: wide, by: [PoleMove(index: PoleIndex(i: 0, j: 2), offset: Vector3(0, 0, 1))])
        }
    }

    @Test func aWideApexAllowsInteriorMoves() async throws {
        let wide = try await kernel.spreadingApex(of: try await dome(), by: 1e-4)
        let moved = try await kernel.movingPoles(of: wide, by: [PoleMove(index: PoleIndex(i: 2, j: 1), offset: Vector3(0, 0, 1))])
        let mesh = try await kernel.tessellate(moved, tolerance: 0.05, angle: 0.5)
        #expect(!mesh.indices.isEmpty)
        // movingPoles skips BRepCheck when its input was invalid, so the input is checked too.
        #expect(try isValid(wide))
        #expect(try isValid(moved))
    }

    private func isValid(_ solid: Solid) throws -> Bool {
        let shape = try #require((solid.storage as? OCCTSolidStorage)?.shape)
        return OCCTKernel.serialized { shape.isValid }
    }

    @Test func aNearlyCollapsedRowIsPinnedToItsCentroid() async throws {
        let nearly = try await kernel.spreadingApex(of: try await dome(), by: 5e-7)
        let source = try await kernel.controlNet(of: nearly).surface
        let row = source.vCount - 1
        let centroid = (0..<source.uCount).map { source.pole($0, row) }.reduce(Vector3.zero, +) * (1 / Double(source.uCount))
        for degree in [3, 4] {
            let rebuilt = try await kernel.rebuilt(
                nearly, as: RebuildSpec(degreeU: degree, degreeV: degree, spansU: 8, spansV: 4)).sheet
            let net = try await kernel.controlNet(of: rebuilt).surface
            for i in 0..<net.uCount { #expect((net.pole(i, net.vCount - 1) - centroid).length < 1e-12) }
        }
    }

    @Test func aWideApexRebuildNeverWidens() async throws {
        let wide = try await kernel.spreadingApex(of: try await dome(), by: 1e-4)
        let before = rowSpread(try await kernel.controlNet(of: wide).surface, row: 2)
        do {
            let rebuilt = try await kernel.rebuilt(wide, as: RebuildSpec(degreeU: 3, degreeV: 3, spansU: 8, spansV: 4)).sheet
            let net = try await kernel.controlNet(of: rebuilt).surface
            #expect(rowSpread(net, row: net.vCount - 1) <= before + 1e-6)
        } catch {
            #expect("\(error)".contains("Rebuilding opens the surface at its apex."))
        }
    }
}
#endif

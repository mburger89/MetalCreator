#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-1 Task 3: sheets, their boundary edges and `planarSurface`.
struct SheetTopologyTests {
    let tag = newTag()

    func message(of error: any Error) -> String? {
        guard case KernelError.invalidInput(let text) = error else { return nil }
        return text
    }

    func rectangle(_ kernel: OCCTKernel, width: Double = 10, height: Double = 20, z: Double = 0,
                   reversed: Bool = false) async throws -> Curve {
        let corners = [Vector3(0, 0, z), Vector3(width, 0, z), Vector3(width, height, z), Vector3(0, height, z)]
        var pieces = corners.indices.map { CurvePiece.line(corners[$0], corners[($0 + 1) % 4]) }
        if reversed { pieces = pieces.reversed().map { .line($0.end, $0.start) } }
        return try await kernel.makeCurve(pieces, tag: tag)
    }

    func circle(_ kernel: OCCTKernel, center: Vector3, radius: Double, sweep: Double = 2 * .pi) async throws -> Curve {
        let start = center + Vector3(radius, 0, 0)
        return try await kernel.makeCurve([.arc(center: center, normal: .unitZ, radius: radius, start: start, sweep: sweep)], tag: tag)
    }

    @Test func aRectangleMakesOneFaceWithFourNamedBoundaryEdges() async throws {
        let kernel = OCCTKernel()
        let sheet = try await kernel.planarSurface([try await rectangle(kernel)], tag: tag)
        let topology = sheet.topology
        #expect(topology.faces.count == 1 && topology.edges.count == 4)
        #expect(topology.faces[0].isOnOpenShell)
        #expect(topology.faces[0].tags == [TopoTag(tag, .startCap)])
        #expect(!sheet.isClosed)
        #expect(topology.edges.allSatisfy { $0.isBoundary && $0.faces == [FaceID(0)] && !$0.isSeam })
        let roles = topology.edges.compactMap { $0.tags.first?.role }
        #expect(Set(roles.map(\.sortKey)).count == 4)
        for k in 0..<4 {
            #expect(roles.contains(.boundary(.piece(loop: 0, segment: k))))
        }
        #expect(topology.edges.allSatisfy { $0.tags.count == 1 })
        #expect(isClose(try await kernel.properties(of: sheet).surfaceArea, 200))
        #expect(isClose(sheet.bounds.max.x, 10) && isClose(sheet.bounds.max.y, 20))
    }

    @Test func pieceKIsTheEdgeOfCurvePieceK() async throws {
        let kernel = OCCTKernel()
        let sheet = try await kernel.planarSurface([try await rectangle(kernel)], tag: tag)
        // Piece 0 runs (0,0) to (10,0), piece 1 (10,0) to (10,20), piece 2 back along y = 20, piece 3 down x = 0.
        let mids = [Vector3(5, 0, 0), Vector3(10, 10, 0), Vector3(5, 20, 0), Vector3(0, 10, 0)]
        for (k, mid) in mids.enumerated() {
            let edge = try #require(sheet.topology.edges.first { $0.tags.first?.role == .boundary(.piece(loop: 0, segment: k)) })
            #expect((edge.midpoint - mid).length < 1e-6)
        }
    }

    @Test func aCircularHoleAddsAFifthEdgeInLoopOne() async throws {
        let kernel = OCCTKernel()
        let hole = try await circle(kernel, center: Vector3(5, 10, 0), radius: 2)
        let sheet = try await kernel.planarSurface([try await rectangle(kernel), hole], tag: tag)
        let topology = sheet.topology
        #expect(topology.faces.count == 1 && topology.edges.count == 5)
        #expect(topology.edges.allSatisfy { $0.isBoundary })
        #expect(topology.edges.filter { $0.tags.first?.role == .boundary(.piece(loop: 1, segment: 0)) }.count == 1)
        #expect(topology.edges.filter { if case .boundary(.piece(0, _)) = $0.tags.first?.role { true } else { false } }.count == 4)
        #expect(isClose(try await kernel.properties(of: sheet).surfaceArea, 200 - 4 * .pi))
    }

    @Test func theOuterLoopIsFoundWhateverTheOrderAndWinding() async throws {
        let kernel = OCCTKernel()
        let hole = try await circle(kernel, center: Vector3(5, 10, 0), radius: 2)
        // The hole first, and the outer loop wound clockwise: loop 0 is still the rectangle.
        let sheet = try await kernel.planarSurface([hole, try await rectangle(kernel, reversed: true)], tag: tag)
        #expect(sheet.topology.edges.filter { $0.tags.first?.role == .boundary(.piece(loop: 1, segment: 0)) }.count == 1)
        #expect(sheet.topology.edges.filter { if case .boundary(.piece(0, _)) = $0.tags.first?.role { true } else { false } }.count == 4)
        #expect(isClose(try await kernel.properties(of: sheet).surfaceArea, 200 - 4 * .pi))
    }

    @Test func aBoxIsClosedWithNoBoundaryEdgesAndItsSeamsAreUnchanged() async throws {
        let kernel = OCCTKernel()
        let box = try await kernel.extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 5, mode: .oneSided, tag: tag)
        #expect(box.isClosed)
        #expect(box.topology.edges.allSatisfy { !$0.isBoundary && $0.tags.isEmpty && $0.faces.count == 2 })
        #expect(box.topology.faces.allSatisfy { !$0.isOnOpenShell })
        let cylinder = try await kernel.extrude(.circle(radius: 2.5, center: .zero, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        #expect(cylinder.isClosed)
        let seams = cylinder.topology.edges.filter(\.isSeam)
        #expect(seams.count == 1 && seams.allSatisfy { !$0.isBoundary && $0.convexity == .smooth })
        #expect(cylinder.topology.edges.filter(\.isBoundary).isEmpty)
        #expect(cylinder.topology.faces.allSatisfy { !$0.isOnOpenShell })
    }

    @Test func aSphereLikePoleIsNotABoundary() async throws {
        let kernel = OCCTKernel()
        // A revolved half disc is a sphere: its poles are degenerate edges and its seam is closed.
        let half = Segment2D.arc(center: Vector2(0, 0), radius: 5, start: .degrees(-90), end: .degrees(90))
        let profile = Profile2D(plane: .xz, segments: [half, .line(Vector2(0, 5), Vector2(0, -5))])
        let sphere = try await kernel.revolve(profile, axis: Axis(origin: .zero, direction: .unitZ), angle: .degrees(360), tag: tag)
        #expect(sphere.isClosed)
        #expect(sphere.topology.edges.filter(\.isBoundary).isEmpty)
    }

    @Test func tessellationDrawsEveryBoundaryEdge() async throws {
        let kernel = OCCTKernel()
        let hole = try await circle(kernel, center: Vector3(5, 10, 0), radius: 2)
        let sheet = try await kernel.planarSurface([try await rectangle(kernel), hole], tag: tag)
        let mesh = try await kernel.tessellate(sheet, tolerance: 0.05, angle: 0.5)
        #expect(!mesh.indices.isEmpty)
        for edge in sheet.topology.edges {
            let line = try #require(mesh.edgePolylines[edge.id])
            #expect(line.count >= 2)
        }
    }

    @Test func aSheetFromAReversedLoopLooksAlongThePlanesNormal() async throws {
        let kernel = OCCTKernel()
        let curve = try await rectangle(kernel, reversed: true)
        let plane = try #require(curve.plane)
        let sheet = try await kernel.planarSurface([curve], tag: tag)
        let normal = try #require(sheet.topology.faces[0].normal)
        #expect(normal.dot(plane.normal) > 0.999)
    }

    @Test func aNonFlatCurveIsRefused() async throws {
        let kernel = OCCTKernel()
        let points = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 10, 4), Vector3(0, 10, 0)]
        let curve = try await kernel.makeCurve(points.indices.map { .line(points[$0], points[($0 + 1) % 4]) }, tag: tag)
        #expect(curve.plane == nil)
        await #expect(throws: KernelError.invalidInput("The curve isn't flat, so it can't be filled with a plane.")) {
            _ = try await kernel.planarSurface([curve], tag: tag)
        }
    }

    @Test func anOpenCurveIsRefused() async throws {
        let kernel = OCCTKernel()
        let open = try await kernel.makeCurve([.line(.zero, Vector3(10, 0, 0)), .line(Vector3(10, 0, 0), Vector3(10, 10, 0))], tag: tag)
        await #expect(throws: KernelError.invalidInput("The curve isn't closed, so it can't be filled.")) {
            _ = try await kernel.planarSurface([open], tag: tag)
        }
    }

    @Test func loopsInDifferentPlanesAreRefused() async throws {
        let kernel = OCCTKernel()
        let upper = try await rectangle(kernel, width: 4, height: 4, z: 3)
        await #expect(throws: KernelError.invalidInput("The curve isn't flat, so it can't be filled with a plane.")) {
            _ = try await kernel.planarSurface([try await rectangle(kernel), upper], tag: tag)
        }
    }

    @Test func loopsThatAreNotOneOuterWithHolesAreRefused() async throws {
        let kernel = OCCTKernel()
        let separate = try await circle(kernel, center: Vector3(30, 10, 0), radius: 2)
        let outside = KernelError.invalidInput("The curves must be one outer loop with holes inside it.")
        await #expect(throws: outside) { _ = try await kernel.planarSurface([try await rectangle(kernel), separate], tag: tag) }
        // A hole that pokes out of the outline.
        let poking = try await circle(kernel, center: Vector3(9, 10, 0), radius: 3)
        await #expect(throws: outside) { _ = try await kernel.planarSurface([try await rectangle(kernel), poking], tag: tag) }
        // Two holes, one inside the other.
        let big = try await circle(kernel, center: Vector3(5, 10, 0), radius: 4)
        let small = try await circle(kernel, center: Vector3(5, 10, 0), radius: 2)
        await #expect(throws: outside) { _ = try await kernel.planarSurface([try await rectangle(kernel), big, small], tag: tag) }
        await #expect(throws: outside) { _ = try await kernel.planarSurface([], tag: tag) }
    }
}
#endif

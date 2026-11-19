#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-4 Task 9: `Kernel.blendSurface(_:_:tag:)` (R10, R12).
struct BlendSurfaceTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    /// A flat ruled Loft Surface over x `from`...`to`, y 0...10, at height `z`. Its start edge is on x = from, its end edge on x = to.
    func flat(from: Double, to: Double, z: Double, length: Double = 10, reversedEnd: Bool = false) async throws -> Solid {
        let first = try await kernel.makeCurve([.line(Vector3(from, 0, z), Vector3(from, length, z))], tag: tag)
        let second = try await kernel.makeCurve(
            [reversedEnd ? .line(Vector3(to, length, z), Vector3(to, 0, z)) : .line(Vector3(to, 0, z), Vector3(to, length, z))], tag: tag)
        return try await kernel.loftSurface([first, second], ruled: true, closed: false, tag: tag)
    }

    func a() async throws -> Solid { try await flat(from: 0, to: 10, z: 0) }
    func b() async throws -> Solid { try await flat(from: 20, to: 30, z: 10) }

    func edge(_ solid: Solid, _ role: BoundaryRole) throws -> EdgeInfo {
        try #require(solid.topology.edges.first { $0.tags.contains(TopoTag(tag, .boundary(role))) })
    }

    func blend(_ first: Solid, _ firstEdge: EdgeID, _ second: Solid, _ secondEdge: EdgeID, _ continuity: PatchContinuity = .g1,
               bulge: Double = 1) async throws -> Solid {
        try await kernel.blendSurface(
            SurfaceBlendEnd(body: first, edge: firstEdge, continuity: continuity, bulge: bulge),
            SurfaceBlendEnd(body: second, edge: secondEdge, continuity: continuity, bulge: bulge), tag: tag)
    }

    func standard(_ continuity: PatchContinuity, bulge: Double = 1) async throws -> (Solid, Solid, Solid) {
        let a = try await a(), b = try await b()
        let result = try await blend(a, try edge(a, .end).id, b, try edge(b, .start).id, continuity, bulge: bulge)
        return (a, b, result)
    }

    func refusal(_ body: () async throws -> Void) async -> String? {
        do { try await body() } catch KernelError.invalidInput(let text) { return text } catch { return "other: \(error)" }
        return nil
    }

    /// Up to nine vertices of the sheet's tessellation, spread over it.
    func points(of solid: Solid) async throws -> [Vector3] {
        let mesh = try await kernel.tessellate(solid, tolerance: 0.01)
        let step = max(1, mesh.positions.count / 9)
        return stride(from: 0, to: mesh.positions.count, by: step).map { mesh.positions[$0] }
    }

    func distance(_ point: Vector3, to solid: Solid) async throws -> Double {
        let face = try #require(solid.topology.faces.first)
        return try await kernel.shortestDistance(between: .point(point), and: .face(solid, face.id)).distance
    }

    @Test func g1BlendIsTangentAtBothEnds() async throws {
        let (a, b, result) = try await standard(.g1)
        let atA = try await kernel.continuity(of: try edge(result, .start).id, in: result, against: FaceID(0), of: a)
        let atB = try await kernel.continuity(of: try edge(result, .end).id, in: result, against: FaceID(0), of: b)
        #expect(atA.grade >= .g1 && atB.grade >= .g1, "angles \(atA.angleGap) \(atB.angleGap)")
        #expect(atA.positionGap <= 1e-4 && atB.positionGap <= 1e-4)
        #expect(result.hasOpenShell)
    }

    @Test func g2BlendIsCurvatureContinuous() async throws {
        let (a, b, result) = try await standard(.g2)
        let atA = try await kernel.continuity(of: try edge(result, .start).id, in: result, against: FaceID(0), of: a)
        let atB = try await kernel.continuity(of: try edge(result, .end).id, in: result, against: FaceID(0), of: b)
        #expect(atA.grade >= .g2, "\(atA.angleGap) \(atA.curvatureGap) \(atA.absoluteCurvatureGap)")
        #expect(atB.grade >= .g2, "\(atB.angleGap) \(atB.curvatureGap) \(atB.absoluteCurvatureGap)")
        #expect(atA.positionGap <= 1e-4 && atB.positionGap <= 1e-4)
    }

    @Test func bulgeChangesTheShape() async throws {
        let (_, _, small) = try await standard(.g1, bulge: 0.5)
        let (_, _, large) = try await standard(.g1, bulge: 1.5)
        var worst = 0.0
        for point in try await points(of: small) { worst = max(worst, try await distance(point, to: large)) }
        #expect(worst > 0.1, "moved \(worst)")
    }

    @Test func g2BlendMeetsACurvedSheet() async throws {
        let a = try await a()
        let line = try await kernel.makeCurve([.line(Vector3(20, 0, 0), Vector3(20, 10, 0))], tag: tag)
        let curved = try await kernel.revolve(line, axis: Axis(origin: Vector3(10, 0, 17.3205), direction: Vector3(0, -1, 0)),
                                              angle: .degrees(60), tag: tag)
        let start = try #require(curved.topology.edges.first {
            $0.kind == .line && abs($0.midpoint.x - 20) < 1e-6 && abs($0.midpoint.z) < 1e-6
        })
        let result = try await blend(a, try edge(a, .end).id, curved, start.id, .g2)
        let atB = try await kernel.continuity(of: try edge(result, .end).id, in: result, against: FaceID(0), of: curved)
        #expect(atB.grade >= .g2, Comment(rawValue: "angle \(atB.angleGap) curvature \(atB.curvatureGap)"))
        #expect(atB.positionGap <= 1e-4)
    }

    @Test func edgesAreNamed() async throws {
        let (_, _, result) = try await standard(.g1)
        #expect(result.topology.faces.count == 1)
        #expect(result.topology.faces[0].tags.contains(TopoTag(tag, .side(loop: 0, segment: 0))))
        func edges(_ role: BoundaryRole) -> [EdgeInfo] {
            result.topology.edges.filter { $0.tags.contains(TopoTag(tag, .boundary(role))) }
        }
        #expect(edges(.start).count == 1 && edges(.end).count == 1)
        #expect(edges(.rail(0)).count == 1 && edges(.rail(1)).count == 1)
        #expect(edges(.start).allSatisfy { abs($0.midpoint.x - 10) < 1e-6 })
        #expect(edges(.end).allSatisfy { abs($0.midpoint.x - 20) < 1e-6 })
        #expect(edges(.rail(0)).allSatisfy { abs($0.midpoint.y) < 1e-6 })
        #expect(edges(.rail(1)).allSatisfy { abs($0.midpoint.y - 10) < 1e-6 })
    }

    @Test func aReversedEdgeIsPaired() async throws {
        let a = try await a()
        let straight = try await b()
        let reversed = try await flat(from: 20, to: 30, z: 10, reversedEnd: false)
        // The same loft with its start line drawn the other way.
        let first = try await kernel.makeCurve([.line(Vector3(20, 10, 10), Vector3(20, 0, 10))], tag: tag)
        let second = try await kernel.makeCurve([.line(Vector3(30, 10, 10), Vector3(30, 0, 10))], tag: tag)
        let turned = try await kernel.loftSurface([first, second], ruled: true, closed: false, tag: tag)
        _ = reversed
        let one = try await blend(a, try edge(a, .end).id, straight, try edge(straight, .start).id)
        let two = try await blend(a, try edge(a, .end).id, turned, try edge(turned, .start).id)
        for point in try await points(of: one) {
            let gap = try await distance(point, to: two)
            #expect(gap < 1e-6, "gap \(gap)")
        }
    }

    @Test func edgesThatTouchRefuse() async throws {
        let a = try await a()
        let touching = try await flat(from: 10, to: 20, z: 0)
        let text = await refusal { _ = try await blend(a, try edge(a, .end).id, touching, try edge(touching, .start).id) }
        #expect(text == "The edges touch; a blend needs a gap between them.")
    }

    @Test func aSolidEdgeUsesTheFaceThatFacesTheOtherEdge() async throws {
        let a = try await a()
        let plan = Profile2D(plane: .xy, segments: [
            .line(Vector2(20, 0), Vector2(30, 0)), .line(Vector2(30, 0), Vector2(30, 10)),
            .line(Vector2(30, 10), Vector2(20, 10)), .line(Vector2(20, 10), Vector2(20, 0)),
        ])
        let box = try await kernel.extrude(plan, distance: 10, mode: .oneSided, tag: newTag())
        let top = try #require(box.topology.faces.first { ($0.normal?.z ?? 0) > 0.99 })
        let rim = try #require(box.topology.edges.first {
            $0.kind == .line && abs($0.midpoint.x - 20) < 1e-6 && abs($0.midpoint.z - 10) < 1e-6
        })
        let result = try await blend(a, try edge(a, .end).id, box, rim.id)
        let found = try await kernel.continuity(of: try edge(result, .end).id, in: result, against: top.id, of: box)
        #expect(found.grade >= .g1, "angle \(found.angleGap)")
        #expect(found.positionGap <= 1e-4)
    }

    @Test func twoEdgesOfOneBodyBlend() async throws {
        let a = try await a(), b = try await b()
        let both = try await kernel.compound([a, b], tag: tag)
        func line(x: Double, z: Double) throws -> EdgeInfo {
            try #require(both.topology.edges.first { $0.kind == .line && abs($0.midpoint.x - x) < 1e-6 && abs($0.midpoint.z - z) < 1e-6 })
        }
        let near = try line(x: 10, z: 0), far = try line(x: 20, z: 10)
        let joined = try await blend(both, near.id, both, far.id)
        let separate = try await blend(a, try edge(a, .end).id, b, try edge(b, .start).id)
        for point in try await points(of: joined) {
            let gap = try await distance(point, to: separate)
            #expect(gap < 1e-6, "gap \(gap)")
        }
    }

    @Test func theSameEdgeTwiceRefuses() async throws {
        let a = try await a()
        let end = try edge(a, .end).id
        let text = await refusal { _ = try await blend(a, end, a, end) }
        #expect(text == "Blend Surface needs two different edges.")
    }

    @Test func g0AndBadBulgesRefuse() async throws {
        let a = try await a(), b = try await b()
        let one = try edge(a, .end).id, two = try edge(b, .start).id
        let g0 = await refusal { _ = try await blend(a, one, b, two, .g0) }
        #expect(g0 == "Blend Surface joins at G1 or G2.")
        for bulge in [0.05, 2.5] {
            let text = await refusal { _ = try await blend(a, one, b, two, bulge: bulge) }
            #expect(text == "The bulge must be from 0.1 to 2.")
        }
    }

    @Test func sectionsPairByArcLength() async throws {
        let a = try await a()
        let long = try await flat(from: 20, to: 30, z: 10, length: 20)
        let result = try await blend(a, try edge(a, .end).id, long, try edge(long, .start).id)
        // The middle section joins the midpoints of the 10 mm and the 20 mm edges: (10, 5, 0) and (20, 10, 10), whose middle is
        // (15, 7.5, 5) at the blend's centre by symmetry, so the point is on the surface.
        #expect(try await distance(Vector3(15, 7.5, 5), to: result) < 1e-6)
    }

    @Test func cancellationStops() async throws {
        let a = try await a(), b = try await b()
        let kernel = self.kernel, tag = self.tag
        let one = try edge(a, .end).id, two = try edge(b, .start).id
        let task = Task {
            try await kernel.blendSurface(
                SurfaceBlendEnd(body: a, edge: one, continuity: .g2, bulge: 1),
                SurfaceBlendEnd(body: b, edge: two, continuity: .g2, bulge: 1), tag: tag)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
#endif

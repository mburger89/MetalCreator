#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// `Kernel.continuity` on OpenCascade (G-b).
struct EdgeContinuityOCCTTests {
    func twoFaceEdges(_ solid: Solid) -> [EdgeInfo] {
        solid.topology.edges.filter { !$0.isSeam && $0.faces.count == 2 && $0.faces[0] != $0.faces[1] }
    }

    @Test func aBoxEdgeIsG0() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(twoFaceEdges(solid).first)
        let found = try await kernel.continuity(along: edge.id, of: solid)
        #expect(abs(found.angleGap - .pi / 2) < 1e-6)
        #expect(found.positionGap < 1e-6)
        #expect(found.grade == .g0)
    }

    @Test func aFilletSpringEdgeIsG1() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let vertical = try #require(solid.topology.edges.first { $0.kind == .line && abs($0.length - 30) < 1e-9 })
        let result = try await kernel.fillet(solid, edges: [vertical.id], radius: 2, tag: newTag())
        // The fillet's spring edges: between the cylinder and a plane.
        let springs = twoFaceEdges(result).filter { edge in
            let kinds = edge.faces.compactMap { result.topology.face($0)?.kind }
            return edge.kind == .line && kinds.contains(.cylinder) && kinds.contains(.plane)
        }
        #expect(springs.count == 2)
        for spring in springs {
            let found = try await kernel.continuity(along: spring.id, of: result)
            #expect(found.angleGap < EdgeContinuity.angleTolerance)
            #expect(found.positionGap < EdgeContinuity.positionTolerance)
            #expect(abs(found.curvatureGap - 1) < 1e-6)
            #expect(abs(found.absoluteCurvatureGap - 0.5) < 1e-6)
            #expect(found.grade == .g1)
        }
    }

    @Test func aCylinderTangentToAPlaneIsG1() async throws {
        let kernel = OCCTKernel()
        // A half-disc "D": a flat on x = 0 meeting a half circle, both tangent to the straight sides at y = ±5.
        let profile = Profile2D(plane: .xy, segments: [
            .line(Vector2(0, -5), Vector2(10, -5)),
            .arc(center: Vector2(10, 0), radius: 5, start: Angle(radians: -.pi / 2), end: Angle(radians: .pi / 2)),
            .line(Vector2(10, 5), Vector2(0, 5)),
            .line(Vector2(0, 5), Vector2(0, -5)),
        ])
        let solid = try await kernel.extrude(profile, distance: 8, mode: .oneSided, tag: newTag())
        let tangent = twoFaceEdges(solid).filter { edge in
            let kinds = edge.faces.compactMap { solid.topology.face($0)?.kind }
            return edge.kind == .line && kinds.contains(.cylinder) && kinds.contains(.plane)
        }
        #expect(tangent.count == 2)
        for edge in tangent {
            let found = try await kernel.continuity(along: edge.id, of: solid)
            #expect(found.grade == .g1)
            #expect(found.angleGap < EdgeContinuity.angleTolerance)
            #expect(abs(found.curvatureGap - 1) < 1e-6)
        }
    }

    @Test func coplanarFacesAreG2() async throws {
        let kernel = OCCTKernel()
        // A rectangle whose long side is two collinear segments: the extrude makes two coplanar side faces sharing an edge.
        let profile = Profile2D(plane: .xy, segments: [
            .line(Vector2(0, 0), Vector2(5, 0)),
            .line(Vector2(5, 0), Vector2(10, 0)),
            .line(Vector2(10, 0), Vector2(10, 4)),
            .line(Vector2(10, 4), Vector2(0, 4)),
            .line(Vector2(0, 4), Vector2(0, 0)),
        ])
        let solid = try await kernel.extrude(profile, distance: 6, mode: .oneSided, tag: newTag())
        let shared = twoFaceEdges(solid).filter { edge in
            let normals = edge.faces.compactMap { solid.topology.face($0)?.normal }
            return normals.count == 2 && normals[0].dot(normals[1]) > 1 - 1e-9
        }
        let edge = try #require(shared.first)
        let found = try await kernel.continuity(along: edge.id, of: solid)
        #expect(found.grade == .g2)
        #expect(found.angleGap < 1e-9 && found.curvatureGap == 0)
    }

    @Test func aSeamIsUnsupported() async throws {
        let kernel = OCCTKernel()
        let solid = try await kernel.extrude(.circle(radius: 5, center: Vector2(0, 0), plane: .xy), distance: 10, mode: .oneSided,
                                             tag: newTag())
        let seam = try #require(solid.topology.edges.first { $0.isSeam })
        await #expect(throws: KernelError.self) { try await kernel.continuity(along: seam.id, of: solid) }
    }
}
#endif

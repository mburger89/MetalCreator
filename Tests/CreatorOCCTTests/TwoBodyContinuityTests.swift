#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-2 Task 1: `Kernel.continuity(of:in:against:of:)`, a sheet's free edge against a face of another body.
struct TwoBodyContinuityTests {
    let tag = newTag()

    /// A flat sheet: the line from `start` to `end` swept by `direction` over `distance`.
    func strip(_ kernel: OCCTKernel, from start: Vector3, to end: Vector3, direction: Vector3,
               distance: Double = 10) async throws -> Solid {
        let curve = try await kernel.makeCurve([.line(start, end)], tag: tag)
        return try await kernel.extrude(curve, direction: direction, distance: distance, symmetric: false, tag: tag)
    }

    func edge(of solid: Solid, near point: Vector3) throws -> EdgeID {
        let found = solid.topology.edges.first { ($0.midpoint - point).length < 1e-6 }
        return try #require(found).id
    }

    func refusal(_ body: () async throws -> Void) async -> String? {
        do { try await body() } catch KernelError.invalidInput(let text) { return text } catch { return nil }
        return nil
    }

    @Test func twoHalvesOfAPlaneAreG2() async throws {
        let kernel = OCCTKernel()
        let a = try await strip(kernel, from: .zero, to: Vector3(10, 0, 0), direction: Vector3(0, 1, 0))
        let b = try await strip(kernel, from: Vector3(0, 10, 0), to: Vector3(10, 10, 0), direction: Vector3(0, 1, 0))
        let found = try await kernel.continuity(of: try edge(of: a, near: Vector3(5, 10, 0)), in: a, against: FaceID(0), of: b)
        #expect(found.grade == .g2)
        #expect(found.positionGap < 1e-6)
    }

    @Test func aCylinderPatchAgainstItsTangentPlaneIsG1() async throws {
        let kernel = OCCTKernel()
        let quarter = CurvePiece.arc(center: .zero, normal: .unitZ, radius: 5, start: Vector3(5, 0, 0), sweep: .pi / 2)
        let arc = try await kernel.makeCurve([quarter], tag: tag)
        let patch = try await kernel.extrude(arc, direction: .unitZ, distance: 10, symmetric: false, tag: tag)
        let plane = try await strip(kernel, from: Vector3(5, 0, 0), to: Vector3(5, -10, 0), direction: .unitZ)
        let found = try await kernel.continuity(of: try edge(of: patch, near: Vector3(5, 0, 5)), in: patch, against: FaceID(0), of: plane)
        #expect(found.grade == .g1)
        #expect(abs(found.absoluteCurvatureGap - 0.2) < 1e-6)
    }

    @Test func aRightAngleIsG0() async throws {
        let kernel = OCCTKernel()
        let a = try await strip(kernel, from: .zero, to: Vector3(10, 0, 0), direction: Vector3(0, 1, 0))
        let b = try await strip(kernel, from: Vector3(0, 10, 0), to: Vector3(10, 10, 0), direction: .unitZ)
        let found = try await kernel.continuity(of: try edge(of: a, near: Vector3(5, 10, 0)), in: a, against: FaceID(0), of: b)
        #expect(abs(found.angleGap - .pi / 2) < 1e-6)
        #expect(found.grade == .g0)
    }

    @Test func aFoldBackIsG0() async throws {
        let kernel = OCCTKernel()
        let a = try await strip(kernel, from: .zero, to: Vector3(10, 0, 0), direction: Vector3(0, 1, 0))
        let b = try await strip(kernel, from: Vector3(0, 10, 0), to: Vector3(10, 10, 0), direction: Vector3(0, -1, 0))
        let found = try await kernel.continuity(of: try edge(of: a, near: Vector3(5, 10, 0)), in: a, against: FaceID(0), of: b)
        #expect(abs(found.angleGap - .pi) < 1e-6)
        #expect(found.grade == .g0)
    }

    @Test func matchingCylinderHalvesBuiltReversedAreG2() async throws {
        let kernel = OCCTKernel()
        let first = CurvePiece.arc(center: .zero, normal: .unitZ, radius: 5, start: Vector3(5, 0, 0), sweep: .pi / 2)
        let second = CurvePiece.arc(center: .zero, normal: .unitZ, radius: 5, start: Vector3(-5, 0, 0), sweep: -.pi / 2)
        let a = try await kernel.extrude(try await kernel.makeCurve([first], tag: tag), direction: .unitZ, distance: 10,
                                         symmetric: false, tag: tag)
        let b = try await kernel.extrude(try await kernel.makeCurve([second], tag: tag), direction: .unitZ, distance: 10,
                                         symmetric: false, tag: tag)
        let found = try await kernel.continuity(of: try edge(of: a, near: Vector3(0, 5, 5)), in: a, against: FaceID(0), of: b)
        #expect(found.grade == .g2)
        #expect(found.absoluteCurvatureGap < 1e-6)
    }

    @Test func aSheetButtingIntoAPlanesMiddleIsG0() async throws {
        let kernel = OCCTKernel()
        let a = try await strip(kernel, from: Vector3(5, 0, 0), to: Vector3(5, 0, 10), direction: Vector3(0, 1, 0))
        let plane = try await strip(kernel, from: Vector3(0, 10, 0), to: Vector3(10, 10, 0), direction: .unitZ)
        // A's far edge, at y = 10, runs across the middle of the wall at y = 10.
        let found = try await kernel.continuity(of: try edge(of: a, near: Vector3(5, 10, 5)), in: a, against: FaceID(0), of: plane)
        #expect(abs(found.angleGap - .pi / 2) < 1e-6)
        #expect(found.grade == .g0)
    }

    @Test func aCylinderFaceAcrossTheSeamIsG2() async throws {
        let kernel = OCCTKernel()
        let degrees = Double.pi / 180
        // Two clockwise arcs on one cylinder (B from 60 to -60 degrees, across the seam at +x; A from 300 to 240). OCCT starts every
        // arc-built face's u at 0, so this cannot put the face's origin in its middle (see the report); it pins the join itself.
        func wall(at degrees: Double, sweep: Double) async throws -> Solid {
            let base = Vector3(5 * cos(degrees * Double.pi / 180), 5 * sin(degrees * Double.pi / 180), 0)
            let arc = CurvePiece.arc(center: .zero, normal: .unitZ, radius: 5, start: base, sweep: sweep * Double.pi / 180)
            let curve = try await kernel.makeCurve([arc], tag: tag)
            return try await kernel.extrude(curve, direction: .unitZ, distance: 10, symmetric: false, tag: tag)
        }
        let a = try await wall(at: 300, sweep: -60)
        let b = try await wall(at: 60, sweep: -120)
        let id = try edge(of: a, near: Vector3(5 * cos(300 * degrees), 5 * sin(300 * degrees), 5))
        let found = try await kernel.continuity(of: id, in: a, against: FaceID(0), of: b)
        #expect(found.grade == .g2)
    }

    @Test func aFaceOnTheSamePlaneBeyondItsBoundaryIsRefused() async throws {
        let kernel = OCCTKernel()
        let a = try await strip(kernel, from: .zero, to: Vector3(10, 0, 0), direction: Vector3(0, 1, 0))
        let b = try await strip(kernel, from: Vector3(20, 10, 0), to: Vector3(30, 10, 0), direction: Vector3(0, 1, 0))
        let id = try edge(of: a, near: Vector3(5, 10, 0))
        let text = await refusal { _ = try await kernel.continuity(of: id, in: a, against: FaceID(0), of: b) }
        #expect(text == "The edge doesn't run along that face.")
    }

    @Test func aFaceElsewhereIsRefused() async throws {
        let kernel = OCCTKernel()
        let a = try await strip(kernel, from: .zero, to: Vector3(10, 0, 0), direction: Vector3(0, 1, 0))
        let b = try await strip(kernel, from: Vector3(0, 0, 10), to: Vector3(10, 0, 10), direction: Vector3(0, 1, 0))
        let id = try edge(of: a, near: Vector3(5, 10, 0))
        let text = await refusal { _ = try await kernel.continuity(of: id, in: a, against: FaceID(0), of: b) }
        #expect(text == "The edge doesn't run along that face.")
    }

    @Test func aSolidsEdgeIsRefused() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 10, 10)
        let b = try await strip(kernel, from: .zero, to: Vector3(10, 0, 0), direction: Vector3(0, 1, 0))
        let id = try #require(solid.topology.edges.first { $0.faces.count == 2 && $0.faces[0] != $0.faces[1] }).id
        let text = await refusal { _ = try await kernel.continuity(of: id, in: solid, against: FaceID(0), of: b) }
        #expect(text == "The edge must be a surface's free edge.")
    }
}
#endif

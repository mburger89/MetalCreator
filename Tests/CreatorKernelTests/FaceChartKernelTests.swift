import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// `Kernel.faceParametrization` and `Kernel.faceCoordinates` (implicit spec §3.5, Face mapping) on the Fake, the default that refuses,
/// and the kernel that is unavailable (the default that refuses is `Kernel`'s extension).
struct FaceChartKernelTests {
    /// A solid whose faces are written by hand: a Fake prism's faces carry no positions.
    func solid(faces: [FaceInfo]) -> Solid {
        Solid(topology: Topology(faces: faces, edges: []), bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: FakeStorage())
    }

    func face(_ id: Int, kind: SurfaceKind = .plane, normal: Vector3?, at centroid: Vector3) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: kind, normal: normal, area: 1, centroid: centroid, tags: [])
    }

    @Test func aPlanarFaceHasMillimetreCoordinatesAndNoPeriod() async throws {
        let kernel = FakeKernel()
        let top = solid(faces: [face(0, normal: .unitZ, at: Vector3(0, 0, 10))])
        let facts = try await kernel.faceParametrization(of: FaceID(0), in: top)
        #expect(facts == FaceParametrization(kind: .plane, uMid: 0, vMid: 0, uScale: 1, vScale: 1))
        #expect(facts.uPeriod == nil && facts.vPeriod == nil && !facts.hasDegenerateEdge)
    }

    @Test func aPointIsAtItsUVAndItsHeightAboveThePlane() async throws {
        let kernel = FakeKernel()
        let top = solid(faces: [face(0, normal: .unitZ, at: Vector3(2, 3, 10))])
        // World X is u and world Y is v on a face that looks up; depth is along the normal, negative on the solid's side.
        let found = try await kernel.faceCoordinates(of: [Vector3(5, 7, 10), Vector3(2, 3, 8), Vector3(0, 3, 14)], on: FaceID(0), in: top)
        #expect(found == [FaceSample(u: 3, v: 4, depth: 0), FaceSample(u: 0, v: 0, depth: -2), FaceSample(u: -2, v: 0, depth: 4)])
    }

    @Test func aFaceLookingAlongXTakesWorldYForU() async throws {
        let kernel = FakeKernel()
        let side = solid(faces: [face(0, normal: .unitX, at: Vector3(5, 0, 0))])
        let found = try await kernel.faceCoordinates(of: [Vector3(7, 2, 3)], on: FaceID(0), in: side)
        // u along Y (X is along the normal), v = normal × u = X × Y = Z.
        #expect(found == [FaceSample(u: 2, v: 3, depth: 2)])
    }

    @Test func aCurvedFaceAndAMissingFaceAreRefused() async throws {
        let kernel = FakeKernel()
        let part = solid(faces: [face(0, kind: .cylinder, normal: .unitZ, at: .zero)])
        await #expect(throws: KernelError.unsupported("face mapping on a curved face")) {
            _ = try await kernel.faceParametrization(of: FaceID(0), in: part)
        }
        await #expect(throws: KernelError.invalidInput("The face doesn't exist on the solid.")) {
            _ = try await kernel.faceCoordinates(of: [.zero], on: FaceID(4), in: part)
        }
    }

    @Test func theUnavailableKernelSaysSo() async throws {
        let kernel = KernelUnavailable()
        let part = solid(faces: [face(0, normal: .unitZ, at: .zero)])
        await #expect(throws: KernelError.unavailable) { _ = try await kernel.faceParametrization(of: FaceID(0), in: part) }
        await #expect(throws: KernelError.unavailable) { _ = try await kernel.faceCoordinates(of: [.zero], on: FaceID(0), in: part) }
    }

    @Test func aCancelledTaskIsSkippedOnEntry() async throws {
        let kernel = FakeKernel()
        let part = solid(faces: [face(0, normal: .unitZ, at: .zero)])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.faceCoordinates(of: [.zero], on: FaceID(0), in: part)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}

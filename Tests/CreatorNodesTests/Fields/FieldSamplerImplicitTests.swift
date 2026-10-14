import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// An implicit read as a field is its signed distance (implicit spec §2.3), and the maths nodes combine it like any field.
struct FieldSamplerImplicitTests {
    /// A sphere at the origin, standing in for `ImplicitSolid` (CreatorImplicit has its own tests).
    struct Ball: ImplicitPayload, Hashable {
        var radius: Double
        var summary: String { "ball" }
        var estimatedBytes: Int { 96 }
        var payloadBounds: BoundingBox { BoundingBox(min: Vector3(-radius, -radius, -radius), max: Vector3(radius, radius, radius)) }
        var lipschitz: Double { 1 }
        func signedDistance(at point: Vector3) -> Double { point.length - radius }
    }

    @Test func anImplicitLeafSamplesToItsSignedDistance() async throws {
        let field = Field.implicit(ImplicitReference(Ball(radius: 5)))
        let values = try await FieldSampler.sample(field, at: [.zero, Vector3(5, 0, 0), Vector3(0, 8, 0)], kernel: FakeKernel())
        #expect(values == [-5, 0, 3])
    }

    @Test func anImplicitLeafCombinesWithTheMaths() async throws {
        let ball = Field.implicit(ImplicitReference(Ball(radius: 5)))
        let field = Field.remap(ball, fromLow: -5, fromHigh: 5, toLow: 0, toHigh: 1, clamped: true)
        let values = try await FieldSampler.sample(field, at: [.zero, Vector3(10, 0, 0)], kernel: FakeKernel())
        #expect(values == [0, 1])
    }
}

import CreatorGeometry
import CreatorGraph

/// A sphere at the origin standing in for `ImplicitSolid` (which lives in CreatorImplicit) in the graph's tests.
struct StubImplicit: ImplicitPayload, Hashable {
    var radius: Double

    var summary: String { "stub(radius \(radius))" }
    var estimatedBytes: Int { 96 }
    var payloadBounds: BoundingBox { BoundingBox(min: Vector3(-radius, -radius, -radius), max: Vector3(radius, radius, radius)) }
    var lipschitz: Double { 1 }
    func signedDistance(at point: Vector3) -> Double { point.length - radius }

    var reference: ImplicitReference { ImplicitReference(self) }
}

/// A mesh payload with a fixed size.
struct StubMesh: MeshPayload {
    var triangleCount: Int
    var estimatedBytes: Int { 16 * 3 * triangleCount + 12 * triangleCount }
}

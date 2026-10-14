import CreatorGeometry
import CreatorGraph

/// An implicit solid travels along wires and sits in field leaves as an `ImplicitPayload` (CreatorGraph cannot name this type).
extension ImplicitSolid: ImplicitPayload {
    public var summary: String { description }
    public var payloadBounds: BoundingBox { bounds }
}

extension ImplicitSolid {
    /// The signed distance at `point` in millimetres, negative inside: the CPU reference (implicit spec §4.1), in `Double`.
    public func signedDistance(at point: Vector3) -> Double {
        CPUEvaluation().distance(self, at: point)
    }

    /// The signed distance at each of `points`, sharing one evaluation's set-up (noise generators, profile measures).
    public func signedDistances(at points: [Vector3]) -> [Double] {
        let evaluation = CPUEvaluation()
        return points.map { evaluation.distance(self, at: $0) }
    }

    /// This solid as a value on a wire.
    public var reference: ImplicitReference { ImplicitReference(self) }
}

extension ImplicitReference {
    /// The solid behind this reference, when it is an `ImplicitSolid` (always, outside tests).
    public var solid: ImplicitSolid? { payload as? ImplicitSolid }
}

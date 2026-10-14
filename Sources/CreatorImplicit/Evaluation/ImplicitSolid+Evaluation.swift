import CreatorGeometry
import CreatorGraph
import Foundation

/// An implicit solid travels along wires and sits in field leaves as an `ImplicitPayload` (CreatorGraph cannot name this type).
extension ImplicitSolid: ImplicitPayload {
    public var summary: String { description }
    public var payloadBounds: BoundingBox { bounds }

    /// For a solid with a baked distance in it (To Implicit): how long the bake took and how much memory it holds (implicit spec §5.2).
    public var inspectorFacts: [PayloadFact] {
        let blocks = bakedBlocks
        guard !blocks.isEmpty else { return [] }
        let seconds = blocks.reduce(0) { $0 + $1.bakeSeconds }
        let bytes = blocks.reduce(0) { $0 + $1.estimatedBytes }
        return [
            PayloadFact("Bake time", "\(seconds.formatted(.number.precision(.fractionLength(2)).locale(.messages))) s"),
            PayloadFact("Bake memory", Int64(bytes).formatted(.byteCount(style: .memory).locale(.messages))),
        ]
    }

    /// The baked distances in the tree, in order.
    var bakedBlocks: [DistanceBlocks] {
        if case .baked(let blocks, _) = self { return [blocks] }
        return children.flatMap(\.bakedBlocks)
    }
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

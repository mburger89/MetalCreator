import CreatorGeometry
import CreatorKernel
import Foundation

/// Why a mesh can't be made.
public enum ImplicitMeshingError: Error, Equatable, Sendable {
    /// The estimate is above half of physical memory (implicit spec §4.2).
    case tooBig(bytes: Int, resolution: Double, suggestion: Double)
    /// The solid has no surface: nothing to mesh.
    case empty

    public var userMessage: String {
        switch self {
        case .tooBig(let bytes, let resolution, let suggestion):
            let gigabytes = (Double(bytes) / 1_000_000_000).formatted(.number.precision(.fractionLength(1)).locale(.messages))
            return "This needs about \(gigabytes) GB at \(resolution.millimetreText(locale: .messages)) mm; "
                + "coarsen to \(suggestion.millimetreText(locale: .messages)) mm or split the part."
        case .empty:
            return "There is no surface to mesh: the shape is empty, or smaller than a voxel."
        }
    }
}

/// The memory a mesh will take, estimated from a coarse pass before the work starts (implicit spec §4.2).
public struct MeshingBudget: Sendable {
    /// The memory the estimate may use: half of physical memory.
    public let limit: Int

    public init(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        limit = Int(physicalMemory / 2)
    }

    /// Bytes per brick the surface passes through: its surface cubes (about 64 on a plane), two triangles each, with the vertex
    /// tables of the mesher (positions, normals, the edge-key map) at about 100 bytes a triangle.
    public static let bytesPerBrick = 64 * 2 * 100

    /// Bytes per brick when the mesh is streamed to a file and never held (Errata D12): the octree's own list of bricks and the cells
    /// it is working through, at most. A refusal still comes before a stream that could not even be planned.
    public static let streamedBytesPerBrick = 256

    /// An estimate of the bytes meshing `solid` at `resolution` takes. A coarse octree at about 64 voxels across counts the bricks the
    /// surface needs there; surface area grows with the square of the finer resolution.
    public static func estimate(for solid: ImplicitSolid, resolution: Double, using evaluator: any ImplicitBatchEvaluator,
                                bytesPerBrick perBrick: Int = MeshingBudget.bytesPerBrick) async throws -> Int {
        try await coarseEstimate(for: solid, resolution: resolution, using: evaluator, bytesPerBrick: perBrick).bytes
    }

    /// The estimate, and whether the coarse pass found any brick at all. Computed in Double and clamped, so a tiny resolution gives a
    /// huge estimate (refused by `check`) rather than a trap in the conversion.
    static func coarseEstimate(for solid: ImplicitSolid, resolution: Double, using evaluator: any ImplicitBatchEvaluator,
                               bytesPerBrick perBrick: Int = MeshingBudget.bytesPerBrick)
        async throws -> (bytes: Int, isEmpty: Bool) {
        precondition(resolution.isFinite && resolution > 0, "the meshing resolution must be positive and finite")
        guard solid.bounds.hasFiniteCorners else { throw ImplicitMeshingError.empty }
        let size = solid.bounds.size
        let coarse = max(resolution, max(size.x, size.y, size.z) / 64)
        let plan = try await BrickPlan.build(for: solid, resolution: coarse, using: evaluator)
        let scale = (coarse / resolution) * (coarse / resolution)
        let bytes = (Double(plan.bricks.count) * scale * Double(perBrick)).rounded(.up)
        return (Int(min(bytes, Double(Int.max / 2))), plan.bricks.isEmpty)
    }

    /// Throws `ImplicitMeshingError.tooBig` when meshing `solid` at `resolution` is estimated over the limit.
    public func check(_ solid: ImplicitSolid, resolution: Double, using evaluator: any ImplicitBatchEvaluator,
                      bytesPerBrick perBrick: Int = MeshingBudget.bytesPerBrick) async throws {
        let (bytes, isEmpty) = try await Self.coarseEstimate(for: solid, resolution: resolution, using: evaluator,
                                                             bytesPerBrick: perBrick)
        // The coarse pass prunes conservatively, so no coarse brick means no surface at the finer resolution either.
        if isEmpty { throw ImplicitMeshingError.empty }
        guard bytes > limit else { return }
        // Bytes follow 1 / resolution², so the resolution that fits the limit is this much coarser.
        let suggestion = (resolution * (Double(bytes) / Double(max(limit, 1))).squareRoot() * 100).rounded(.up) / 100
        throw ImplicitMeshingError.tooBig(bytes: bytes, resolution: resolution, suggestion: suggestion)
    }
}

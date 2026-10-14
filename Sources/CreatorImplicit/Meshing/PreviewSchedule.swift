import CreatorGeometry

/// The passes of a progressive preview (implicit spec §4.3): the first at 128 cells across the largest dimension, then the voxel size
/// halves each pass until the preview resolution. With `.automatic` that is the finest the last pass says meshes in under a second.
public struct PreviewSchedule: Sendable {
    /// What the passes work towards.
    public enum Target: Hashable, Sendable {
        /// The finest resolution estimated to mesh in under `PreviewSchedule.budgetSeconds`.
        case automatic
        /// A voxel size in millimetres (the Mesh node's `preview resolution`).
        case fixed(Double)
    }

    public static let budgetSeconds = 1.0
    /// The cells across the largest dimension in the first pass.
    public static let firstPassCells = 128.0
    /// The finest resolution a preview pass uses on its own.
    public static let finest = 0.05

    public let target: Target

    public init(_ target: Target) {
        self.target = target
    }

    /// The first pass's voxel size for a solid in `box`.
    public func firstResolution(for box: BoundingBox) -> Double {
        let longest = max(box.size.x, box.size.y, box.size.z)
        let coarse = max(longest / Self.firstPassCells, Self.finest)
        if case .fixed(let wanted) = target { return max(coarse, wanted) }
        return coarse
    }

    /// The voxel size of the pass after one at `resolution` that took `seconds`, or `nil` when the preview is as fine as it goes.
    /// Halving the voxel size makes four times as many surface voxels, so the next pass is estimated at four times as long.
    public func next(after resolution: Double, seconds: Double) -> Double? {
        let finer = resolution / 2
        switch target {
        case .fixed(let wanted):
            guard resolution > wanted * (1 + 1e-9) else { return nil }
            return max(finer, wanted)
        case .automatic:
            guard finer >= Self.finest, 4 * seconds < Self.budgetSeconds else { return nil }
            return finer
        }
    }
}

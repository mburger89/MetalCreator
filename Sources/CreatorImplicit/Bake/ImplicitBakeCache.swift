import CreatorGeometry
import CreatorKernel
import Foundation

/// Distance blocks baked from solids (implicit spec §4.4), kept so editing a number downstream of To Implicit doesn't bake again. Keyed
/// by the solid object (its identity) and the tolerance; least recently used entries go first once the blocks hold more than
/// `capacity` bytes (512 MB by default). An entry holds its solid, so the identity can't be reused while the entry exists.
public actor ImplicitBakeCache {
    /// What a bake made.
    public struct Baked: Sendable {
        public var blocks: DistanceBlocks
        /// The sample spacing used, which is more than `DistanceBaker.spacing(forTolerance:)` when the part was too big for the budget.
        public var spacing: Double
        /// How long the tessellation, the BVH and the bake took.
        public var seconds: Double
        /// The tolerance the OCCT tessellation was made at.
        public var tolerance: Double
    }

    /// The cache every To Implicit node shares.
    public static let shared = ImplicitBakeCache()

    private struct Key: Hashable {
        var solid: ObjectIdentifier
        var tolerance: Double
    }

    private struct Entry {
        var solid: Solid
        var baked: Baked
        var used: Int
    }

    public let capacity: Int
    private var entries: [Key: Entry] = [:]
    private var clock = 0
    /// How many bakes have run (a hit doesn't count).
    public private(set) var bakeCount = 0

    public init(capacity: Int = 512 * 1024 * 1024) {
        self.capacity = capacity
    }

    public var entryCount: Int { entries.count }
    public var totalBytes: Int { entries.values.reduce(0) { $0 + $1.baked.blocks.estimatedBytes } }

    /// The baked distance of `solid`, from the cache or made now: the kernel tessellates it at `tolerance`, a BVH measures the
    /// distance and the sign comes from pseudonormals, and `DistanceBaker` samples it.
    /// - Throws: `MeshDistanceError.notClosed` for a solid whose tessellation has holes, and anything the kernel throws.
    public func baked(for solid: Solid, tolerance: Double, kernel: any Kernel) async throws -> Baked {
        let key = Key(solid: ObjectIdentifier(solid), tolerance: tolerance)
        clock += 1
        if var hit = entries[key] {
            hit.used = clock
            entries[key] = hit
            return hit.baked
        }
        let clockStart = ContinuousClock.now
        let mesh = try await kernel.tessellate(solid, tolerance: tolerance)
        let distance = try SignedDistanceMesh(positions: mesh.positions, indices: mesh.indices)
        let result = try await DistanceBaker.bake(bounds: distance.bounds, spacing: DistanceBaker.spacing(forTolerance: tolerance)) {
            distance.signedDistance(at: $0)
        }
        let seconds = clockStart.duration(to: .now) / .seconds(1)
        let baked = Baked(blocks: result.blocks.timed(seconds), spacing: result.spacing, seconds: seconds, tolerance: tolerance)
        bakeCount += 1
        clock += 1
        entries[key] = Entry(solid: solid, baked: baked, used: clock)
        evict()
        return baked
    }

    /// Drops the least recently used entries until the rest fit, keeping the newest.
    private func evict() {
        var bytes = totalBytes
        for (key, entry) in entries.sorted(by: { $0.value.used < $1.value.used }) where bytes > capacity && entries.count > 1 {
            entries[key] = nil
            bytes -= entry.baked.blocks.estimatedBytes
        }
    }
}

import CreatorGeometry
import CreatorKernel

/// Kernel distances, remembered per distance source and point set (fields spec §2.2), so sampling the same points again
/// after an edit downstream costs nothing. The evaluator owns one (`Evaluator.fieldDistances`) and hands it to every node
/// through `EvalContext.fieldDistances`; `FieldSampler` asks it for every kernel distance.
///
/// A hit needs the same distance source (`DistanceTarget.identity`), the same sign, and the same points: the points' hash
/// finds the entry and an exact comparison confirms it, so a collision costs a kernel call, never a wrong number. An entry
/// keeps its target alive, so the solid's identity can't be reused by another object while the entry exists; that also pins
/// the solid, so an entry's size counts it (`Solid.estimatedBytes`) with its points and distances. At most `budgetBytes` are
/// kept (64 MB by default), least recently used first.
public actor FieldDistanceCache {
    public static let defaultBudgetBytes = 64 * 1024 * 1024

    private struct Key: Hashable {
        let target: DistanceTarget.Identity
        let signed: Bool
        let pointsDigest: Int
        let pointCount: Int
    }

    private struct Entry {
        /// Held so the solid in `Key.target` stays the same object for as long as the entry lives.
        let target: DistanceTarget
        let points: [Vector3]
        let distances: [Double]
        var lastUse: Int

        /// 24 bytes a point, 8 a distance, a fixed overhead, and the solid the entry keeps alive: it pins the OCCT shape and the
        /// topology tables for as long as the entry lives, and the evaluator's own cache budget never sees it.
        var bytes: Int { points.count * 24 + distances.count * 8 + 128 + target.solid.estimatedBytes }
    }

    public let budgetBytes: Int
    private var entries: [Key: Entry] = [:]
    private var clock = 0
    private var usedBytes = 0
    public private(set) var hits = 0
    public private(set) var misses = 0

    public init(budgetBytes: Int = FieldDistanceCache.defaultBudgetBytes) {
        self.budgetBytes = budgetBytes
    }

    public var entryCount: Int { entries.count }
    public var totalBytes: Int { usedBytes }

    /// The distances from `points` to `target`, from the cache when this source and these points were measured before,
    /// else from `kernel` (then remembered). A cancelled or failed measurement is not remembered.
    public func distances(from points: [Vector3], to target: DistanceTarget, signed: Bool,
                          kernel: any Kernel) async throws -> [Double] {
        // Only a solid has a sign; for faces and edges both signs are one entry.
        var isSolid = false
        if case .solid = target { isSolid = true }
        let effectiveSign = signed && isSolid
        var hasher = Hasher()
        hasher.combine(points)
        let key = Key(target: target.identity, signed: effectiveSign, pointsDigest: hasher.finalize(), pointCount: points.count)
        if var entry = entries[key], entry.points == points {
            clock += 1
            entry.lastUse = clock
            entries[key] = entry
            hits += 1
            return entry.distances
        }
        misses += 1
        let found = try await kernel.distances(from: points, to: target, signed: signed)
        remember(Entry(target: target, points: points, distances: found, lastUse: 0), for: key)
        return found
    }

    /// Forgets everything.
    public func clear() {
        entries.removeAll()
        usedBytes = 0
    }

    private func remember(_ entry: Entry, for key: Key) {
        guard entry.bytes <= budgetBytes else { return }
        if let old = entries[key] { usedBytes -= old.bytes }
        clock += 1
        var stored = entry
        stored.lastUse = clock
        entries[key] = stored
        usedBytes += stored.bytes
        while usedBytes > budgetBytes, let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            usedBytes -= oldest.value.bytes
            entries[oldest.key] = nil
        }
    }
}

import CreatorKernel

/// An LRU cache of successful node results, bounded by estimated bytes (spec §4.4).
struct ResultCache: Sendable {
    private struct Entry: Sendable {
        var result: NodeResult
        var node: NodeID
        var bytes: Int
        var lastUse: UInt64
    }

    let budgetBytes: Int
    private var entries: [CacheKey: Entry] = [:]
    private var useCounter: UInt64 = 0
    private(set) var totalBytes = 0

    init(budgetBytes: Int) {
        self.budgetBytes = budgetBytes
    }

    var count: Int { entries.count }

    mutating func result(for key: CacheKey) -> NodeResult? {
        guard var entry = entries[key] else { return nil }
        useCounter += 1
        entry.lastUse = useCounter
        entries[key] = entry
        return entry.result
    }

    mutating func insert(_ result: NodeResult, for key: CacheKey, node: NodeID) {
        if let old = entries[key] { totalBytes -= old.bytes }
        useCounter += 1
        let bytes = result.estimatedBytes
        entries[key] = Entry(result: result, node: node, bytes: bytes, lastUse: useCounter)
        totalBytes += bytes
        evictIfNeeded(protecting: key)
    }

    /// Drops entries of nodes that no longer exist in the graph.
    mutating func removeEntries(notIn nodes: Set<NodeID>) {
        for (key, entry) in entries where !nodes.contains(entry.node) {
            entries[key] = nil
            totalBytes -= entry.bytes
        }
    }

    private mutating func evictIfNeeded(protecting key: CacheKey) {
        while totalBytes > budgetBytes,
              let victim = entries.filter({ $0.key != key }).min(by: { $0.value.lastUse < $1.value.lastUse }) {
            entries[victim.key] = nil
            totalBytes -= victim.value.bytes
        }
    }
}

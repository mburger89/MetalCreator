/// Identity of one node evaluation: its type, constants and upstream keys (spec §4.4).
/// Uses `Hasher`, which is seeded per process. That's fine because the cache lives in memory.
struct CacheKey: Hashable, Sendable {
    let digest: Int
}

extension CacheKey {
    /// This key with the stamps of the files a result depended on mixed in, so what is downstream of a node whose file changed
    /// is keyed differently and runs again too. Unchanged for a node with no dependencies.
    func including(_ dependencies: [FileDependency]) -> CacheKey {
        guard !dependencies.isEmpty else { return self }
        var hasher = Hasher()
        hasher.combine(digest)
        for dependency in dependencies { hasher.combine(dependency) }
        return CacheKey(digest: hasher.finalize())
    }
}

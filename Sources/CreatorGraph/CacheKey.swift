/// Identity of one node evaluation: its type, constants and upstream keys (spec §4.4).
/// Uses `Hasher`, which is seeded per process. That's fine because the cache lives in memory.
struct CacheKey: Hashable, Sendable {
    let digest: Int
}

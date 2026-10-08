import CreatorGraph

/// Bounds on generated lists, so a typo ("count 1000000") gives a message instead of a hang.
enum GeneratorLimit {
    static let maximumItems = 10_000

    /// Rejects a negative count or one over the limit.
    static func check(_ count: Int, _ name: SocketName) throws {
        guard count >= 0 else { throw NodeError.invalidValue("“\(name)” can't be negative.") }
        guard count <= maximumItems else {
            throw NodeError.invalidValue("“\(name)” can be at most \(maximumItems.display) items.")
        }
    }
}

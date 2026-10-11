import CreatorGraph

/// The most instances one pattern makes (patterns spec §3): B-rep booleans with more tools than this stop being
/// interactive, so a typo ("count 100000") gives a message instead of a hang, as Grid Points' limit does.
enum PatternLimit {
    static let maximumInstances = 2_000

    /// Refuses a pattern of more than `maximumInstances`.
    static func check(_ count: Int) throws {
        guard count <= maximumInstances else {
            throw NodeError.invalidValue("Patterns are limited to \(maximumInstances.display) instances.")
        }
    }
}

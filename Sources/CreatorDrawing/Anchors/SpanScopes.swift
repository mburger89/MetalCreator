import CreatorKernel
import Synchronization

/// The restricted topology of each part span, kept for ONE compose (or one refresh pass) of ONE topology (DR-5 minors R15).
///
/// A pass makes a fresh cache for the topology it resolves against, binds it to `current` while it runs and drops it at the end,
/// so a changed topology can never be served a stale restriction. The key is the span alone because the cache never outlives
/// its topology. `onRestrict` is the test hook: it is told each time a span is actually restricted.
final class SpanScopes: Sendable {
    @TaskLocal static var current: SpanScopes?

    private let held = Mutex<[PartSpan: Topology]>([:])
    private let onRestrict: (@Sendable (PartSpan) -> Void)?

    init(onRestrict: (@Sendable (PartSpan) -> Void)? = nil) { self.onRestrict = onRestrict }

    /// The test hook, read when a pass makes its cache; bound by a test around the compose it counts.
    @TaskLocal static var observer: (@Sendable (PartSpan) -> Void)?

    /// A cache for a pass, carrying the observer bound for the task.
    static func forPass() -> SpanScopes { SpanScopes(onRestrict: observer) }

    func restricted(_ topology: Topology, to span: PartSpan) -> Topology {
        if let found = held.withLock({ $0[span] }) { return found }
        onRestrict?(span)
        let made = topology.restricted(toFaces: span.faces)
        held.withLock { $0[span] = made }
        return made
    }

    /// Runs `body` with a fresh cache bound (for one topology).
    static func withFreshCache<T>(_ body: () -> T) -> T {
        $current.withValue(forPass(), operation: body)
    }
}

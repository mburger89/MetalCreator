/// How much an entity can still move after a solve (spec §4).
public enum EntityFreedom: Hashable, Sendable {
    /// Some of its unknowns lie in the Jacobian's null space: it can still move.
    case free
    /// Fully determined (or projected, which never moves).
    case fixed
    /// Named by a conflict.
    case conflicting
}

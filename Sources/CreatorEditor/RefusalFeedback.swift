import CreatorKernel

/// A refused edit: the message shown in the panel and the node that shakes (spec §6.2).
/// `serial` increases with every refusal, so the message timer of an older refusal never
/// clears a newer one.
public struct RefusalFeedback: Equatable, Sendable {
    public var message: String
    public var node: NodeID?
    public var serial: Int
}

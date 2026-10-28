import CreatorKernel

/// One edit that is still on trial (dimensions spec §7): everything `DocumentModel.withdraw(_:)` needs to take it back
/// with no redo entry, and everything `DocumentModel.newProblem(in:)` needs to judge its result.
public struct TentativeStep: Sendable {
    /// The top-level nodes the step touched and their downstream closure (the stale set), taken before it was applied.
    public let watched: Set<NodeID>
    let contentBefore: GraphContent
    let contentAfter: GraphContent
    let historyBefore: UndoStack
    /// The `.error` messages of the top-level results before the step, so an error that was already there is not new.
    let errorsBefore: [NodeID: String]
}

/// The error a tentative step caused: the node that failed and the first line of its message.
public struct StepProblem: Sendable, Equatable {
    public var node: NodeID
    public var message: String

    public init(node: NodeID, message: String) {
        self.node = node
        self.message = message
    }
}

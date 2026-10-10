extension Graph {
    /// Every comment of the graph, notes and frames alike.
    public var commentIDs: Set<CommentID> {
        Set(stickies.keys).union(frames.keys)
    }

    /// The four comment commands (canvas comments spec 2026-10-09 §7), applied to this graph. Comments never affect
    /// evaluation (`GraphCommand.affectsResults`). A set command adds the comment or replaces it whole, so a move,
    /// a resize and an edit are all one command that carries the comment's new value; its inverse carries the old.
    /// Refused, changing nothing: a rectangle that isn't finite or has a negative size, an ID the other kind holds,
    /// and removing a comment that isn't there.
    mutating func applyComment(_ command: GraphCommand) throws(GraphError) -> GraphCommand {
        switch command {
        case .setSticky(let note):
            try Self.requireValid(note.frame, id: note.id, otherKind: frames[note.id] != nil)
            let old = stickies.updateValue(note, forKey: note.id)
            return old.map { .setSticky($0) } ?? .removeSticky(note.id)
        case .removeSticky(let id):
            guard let old = stickies.removeValue(forKey: id) else { throw Self.missing }
            return .setSticky(old)
        case .setFrame(let comment):
            try Self.requireValid(comment.frame, id: comment.id, otherKind: stickies[comment.id] != nil)
            let old = frames.updateValue(comment, forKey: comment.id)
            return old.map { .setFrame($0) } ?? .removeFrame(comment.id)
        case .removeFrame(let id):
            guard let old = frames.removeValue(forKey: id) else { throw Self.missing }
            return .setFrame(old)
        default:
            throw .invalidValue("Not a comment edit.")  // `apply` routes only the four comment commands here.
        }
    }

    private static let missing = GraphError.invalidValue("That comment is gone.")

    private static func requireValid(_ rect: CanvasRect, id: CommentID, otherKind: Bool) throws(GraphError) {
        guard rect.origin.isFinite, rect.size.isFinite, rect.size.x >= 0, rect.size.y >= 0 else {
            throw .invalidValue("Enter a finite number.")
        }
        if otherKind { throw .invalidValue("Comment \(id) already exists as the other kind.") }
    }
}

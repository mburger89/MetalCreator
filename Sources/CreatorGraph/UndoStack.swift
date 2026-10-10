/// Undo history of applied commands, with slider-drag coalescing (spec §4.5).
public struct UndoStack: Sendable {
    public struct Entry: Sendable, Equatable {
        /// What redo re-applies: the latest command of a coalesced run.
        public var forward: GraphCommand
        /// What undo applies: the inverse of the first command of a coalesced run.
        public var inverse: GraphCommand
        public var coalescingKey: String?
        /// What the Edit menu calls the step ("Add Note"): the first record's, for a coalesced run.
        public var name: String
    }

    public private(set) var undoEntries: [Entry] = []
    public private(set) var redoEntries: [Entry] = []
    private var isCoalescingOpen = false

    public init() {}

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }
    /// The name of the step Undo would take back, or `nil` with nothing to undo.
    public var undoName: String? { undoEntries.last?.name }
    /// The name of the step Redo would re-apply, or `nil` with nothing to redo.
    public var redoName: String? { redoEntries.last?.name }

    /// Records an applied command. Consecutive records with the same non-nil key, with no
    /// `endCoalescing()` between them, merge into one entry that keeps the first inverse and the first `name`.
    /// `name` defaults to "Edit" for the direct callers in tests; `DocumentModel` always passes one.
    public mutating func record(forward: GraphCommand, inverse: GraphCommand, coalescingKey: String?,
                                name: String = UndoName.edit) {
        redoEntries.removeAll()
        if let key = coalescingKey, isCoalescingOpen, let last = undoEntries.last, last.coalescingKey == key {
            undoEntries[undoEntries.count - 1].forward = forward
        } else {
            undoEntries.append(Entry(forward: forward, inverse: inverse, coalescingKey: coalescingKey, name: name))
        }
        isCoalescingOpen = coalescingKey != nil
    }

    /// Ends the current drag, so the next record starts a new undo step.
    public mutating func endCoalescing() {
        isCoalescingOpen = false
    }

    public mutating func takeUndo() -> Entry? {
        isCoalescingOpen = false
        guard let entry = undoEntries.popLast() else { return nil }
        redoEntries.append(entry)
        return entry
    }

    public mutating func takeRedo() -> Entry? {
        isCoalescingOpen = false
        guard let entry = redoEntries.popLast() else { return nil }
        undoEntries.append(entry)
        return entry
    }
}

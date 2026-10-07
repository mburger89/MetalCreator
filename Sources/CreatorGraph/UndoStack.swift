/// Undo history of applied commands, with slider-drag coalescing (spec §4.5).
public struct UndoStack: Sendable {
    public struct Entry: Sendable, Equatable {
        /// What redo re-applies: the latest command of a coalesced run.
        public var forward: GraphCommand
        /// What undo applies: the inverse of the first command of a coalesced run.
        public var inverse: GraphCommand
        public var coalescingKey: String?
    }

    public private(set) var undoEntries: [Entry] = []
    public private(set) var redoEntries: [Entry] = []
    private var isCoalescingOpen = false

    public init() {}

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }

    /// Records an applied command. Consecutive records with the same non-nil key, with no
    /// `endCoalescing()` between them, merge into one entry that keeps the first inverse.
    public mutating func record(forward: GraphCommand, inverse: GraphCommand, coalescingKey: String?) {
        redoEntries.removeAll()
        if let key = coalescingKey, isCoalescingOpen, let last = undoEntries.last, last.coalescingKey == key {
            undoEntries[undoEntries.count - 1].forward = forward
        } else {
            undoEntries.append(Entry(forward: forward, inverse: inverse, coalescingKey: coalescingKey))
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

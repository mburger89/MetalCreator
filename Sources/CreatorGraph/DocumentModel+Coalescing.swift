extension DocumentModel {
    /// Takes back the run of steps coalesced under `key` as if it never happened: its inverse is applied and no redo is left.
    /// False (nothing changed) when the last step is not that run.
    @discardableResult
    public func discardCoalescedStep(key: String) -> Bool {
        guard let entry = undoStack.discardCoalesced(key: key) else { return false }
        tentativeStep = nil
        heldReport = nil
        replay(entry.inverse)
        return true
    }
}

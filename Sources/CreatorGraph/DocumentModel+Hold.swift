import CreatorKernel

/// Holding results and withdrawing a step (dimensions spec §7). These are the document's own members, kept apart only to
/// keep `DocumentModel.swift` short; they work on its stored `undoStack`, `heldReport` and `tentativeStep`.
extension DocumentModel {
    /// From now on a finished evaluation is kept back instead of published, and an edit marks nothing as evaluating: the
    /// results on screen stay as they are while a step is checked. Pair with `releaseResults()`, also after a throw. Holds
    /// nest: results publish again only when every hold has been released.
    public func holdResults() {
        holdDepth += 1
    }

    /// Ends one hold; when the last one ends, publishes the report held meanwhile, if one arrived. A report still to come
    /// publishes as usual. An unpaired release does nothing.
    public func releaseResults() {
        guard holdDepth > 0 else { return }
        holdDepth -= 1
        guard holdDepth == 0 else { return }
        if let report = heldReport {
            heldReport = nil
            apply(report)
        }
    }

    /// The step the last `perform` took, or `nil` after an undo, a redo, a withdrawal or a coalesced edit.
    public func lastStep() -> TentativeStep? {
        tentativeStep
    }

    /// The first error `step` caused: among its watched nodes, in evaluation order, one whose result (the held report's while
    /// holding, else the published one) is an error with a message it did not already have. `nil` when there is none, and
    /// while the report for the step's content has not arrived (await `waitForEvaluation()` first). Warnings never count.
    public func newProblem(in step: TentativeStep) -> StepProblem? {
        let current: [NodeID: NodeResult]
        if isHoldingResults {
            guard let held = heldReport else { return nil }
            current = held.results
        } else {
            current = results
        }
        for id in graph.evaluationOrder(for: step.watched).order where step.watched.contains(id) {
            guard case .error(let message)? = current[id]?.state, step.errorsBefore[id] != message else { continue }
            let firstLine = message.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? message
            return StepProblem(node: id, message: firstLine)
        }
        return nil
    }

    /// Takes `step` back: the content and the undo history return to what they were before it, so there is no redo entry and
    /// an earlier redo entry survives. Only while `step` is still the latest thing done (the content is what it produced and
    /// the history has exactly its one entry more); otherwise returns `false` and changes nothing. The evaluation that
    /// follows finds everything in the cache.
    @discardableResult
    public func withdraw(_ step: TentativeStep) -> Bool {
        guard content == step.contentAfter,
              undoStack.undoEntries.count == step.historyBefore.undoEntries.count + 1 else { return false }
        content = step.contentBefore
        undoStack = step.historyBefore
        heldReport = nil
        tentativeStep = nil
        scheduleEvaluation()
        return true
    }

    /// The `.error` messages of the top-level results.
    /// While holding, the held report's results are what the step started from; else the published ones.
    var topLevelErrors: [NodeID: String] {
        let current = isHoldingResults ? (heldReport?.results ?? results) : results
        return current.compactMapValues { result in
            if case .error(let message) = result.state { message } else { nil }
        }
    }
}

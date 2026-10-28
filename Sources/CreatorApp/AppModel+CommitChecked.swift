import CreatorGraph
import CreatorKernel
import CreatorViewport

/// Edits that are tried before they are kept (spec §7): the result is held back while the evaluation runs, and an edit that
/// makes a new error is taken back with no redo entry.
extension AppModel {
    /// Holds results, performs `command` at `path` as one step named `name`, waits for the evaluation, and withdraws the step when it
    /// made a new error (spec §7). The hold is released on every path.
    func commitChecked(_ command: GraphCommand, at path: GraphPath, name: String) async -> DimensionCommitOutcome {
        let document = document  // New or Open during the check replaces `self.document`; this one is released regardless
        document.holdResults()
        do {
            try document.perform(command, at: path, name: name)
        } catch {
            document.releaseResults()
            return .refused(Self.message(of: error))
        }
        let refusal = await checkLastStep(of: document)
        document.releaseResults()
        return refusal.map(DimensionCommitOutcome.refused) ?? .accepted
    }

    /// After a step already performed: waits, and withdraws it on a new error; the refusal text or nil. A step the user
    /// superseded meanwhile (Undo, another edit, deleting the node) is left alone and counts as accepted.
    func checkLastStep() async -> String? {
        await checkLastStep(of: document)
    }

    private func checkLastStep(of document: DocumentModel) async -> String? {
        guard let step = document.lastStep() else { return nil }
        await document.waitForEvaluation()
        guard let problem = document.newProblem(in: step), document.withdraw(step) else { return nil }
        return "\(label(of: problem.node, in: document)): \(problem.message)"
    }

    /// The node's name, else its type's display name.
    private func label(of node: NodeID, in document: DocumentModel) -> String {
        guard let found = document.graph.nodes[node] else { return "That node" }
        if !found.name.isEmpty { return found.name }
        return registry[found.typeID]?.displayName ?? found.typeID
    }

    private static func message(of error: GraphError) -> String {
        switch error {
        case .invalidValue(let message): message
        case .nodeNotFound: "That node no longer exists."
        case .parameterNotFound: "That parameter no longer exists."
        case .duplicateNode, .linkNotFound, .invalidConnection: "That change isn't possible."
        }
    }

    /// The text typed for a feature dimension: checked, then committed as one checked step.
    func commitFeatureValue(_ text: String, to id: OverlayDimensionID) async -> DimensionCommitOutcome {
        guard let dimension = featureDimensions[id] else { return .refused("That dimension is gone.") }
        let value: Double
        switch FeatureDimensionEditing.value(from: text, for: dimension, units: units) {
        case .failure(let refusal): return .refused(refusal.message)
        case .success(nil): return .accepted
        case .success(let typed?): value = typed
        }
        switch FeatureDimensionEditing.command(for: dimension, value: value, graph: editor.graph, document: document,
                                               level: editor.graphPath) {
        case .failure(let refusal): return .refused(refusal.message)
        case .success(let (command, path, name)): return await commitChecked(command, at: path ?? .root, name: name)
        }
    }
}

import CreatorEditor
import CreatorGraph
import Observation

extension AppModel {
    /// A node the document is evaluating, with what the chip orders by.
    struct EvaluatingNode: Equatable {
        var title: String
        var id: String
        var isOutput: Bool
        /// How long the node took the last time it ran; zero when that isn't known.
        var lastDuration: Duration
    }

    /// The names that word the chip, most likely first: Output nodes left out (they only wait for what feeds them), the rest by
    /// how long each took last time, longest first, then name, then ID. This is an informed guess: the evaluator reports no live
    /// per-node progress, so the first name is the node that has been slowest before, not one known to be running now.
    nonisolated static func chipNames(of nodes: [EvaluatingNode]) -> [String] {
        nodes.filter { !$0.isOutput }
            .sorted { lhs, rhs in
                if lhs.lastDuration != rhs.lastDuration { return lhs.lastDuration > rhs.lastDuration }
                return lhs.title == rhs.title ? lhs.id < rhs.id : lhs.title < rhs.title
            }
            .map(\.title)
    }

    /// The nodes the document is evaluating now, by the name the graph panel shows, ordered by `chipNames(of:)`. This is the state
    /// the graph panel's badge spinner reads (`NodeState.evaluating` in `DocumentModel.results`). They only word the chip: a node
    /// new to the graph, or any node while a file opens, has no result yet and is not named, and a stale downstream node counts
    /// as running until the evaluation ends. Last times are `DocumentModel.lastDurations`, which is not observed.
    func evaluatingNodeNames() -> [String] {
        let graph = document.graph
        let registry = document.registry
        var evaluating: [EvaluatingNode] = []
        for (id, result) in document.results where result.state == .evaluating {
            guard let node = graph.nodes[id] else { continue }
            evaluating.append(EvaluatingNode(title: NodeShape(node, in: graph, registry: registry).title, id: id.rawValue.uuidString,
                                             isOutput: node.isOutput, lastDuration: document.lastDurations[id] ?? .zero))
        }
        return Self.chipNames(of: evaluating)
    }

    /// Follows the document's evaluating nodes into `slowEvaluation`, once; the first change schedules one update, which follows
    /// again. A registration made for a document since replaced is ignored by its generation.
    func followEvaluation() {
        evaluationObservationGeneration += 1
        let generation = evaluationObservationGeneration
        evaluationUpdatePending = false
        let (isRunning, names) = withObservationTracking {
            (document.isEvaluating, evaluatingNodeNames())
        } onChange: { [weak self] in
            // Called as the property is about to change, on the actor that changes it; the update runs after the change.
            MainActor.assumeIsolated { self?.scheduleEvaluationFollow(generation) }
        }
        slowEvaluation.follow(running: isRunning, names: names)
    }

    private func scheduleEvaluationFollow(_ generation: Int) {
        guard generation == evaluationObservationGeneration, !evaluationUpdatePending else { return }
        evaluationUpdatePending = true
        Task { [weak self] in self?.followEvaluation() }
    }
}

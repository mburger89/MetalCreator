import CreatorEditor
import CreatorGraph
import Observation

extension AppModel {
    /// The nodes the document is evaluating now, by the name the graph panel shows, in a stable order (name, then ID). This is the
    /// state the graph panel's badge spinner reads (`NodeState.evaluating` in `DocumentModel.results`); a node new to the graph, or
    /// every node while a file opens, has no result yet and so is not named.
    func evaluatingNodeNames() -> [String] {
        let graph = document.graph
        let registry = document.registry
        var named: [(title: String, id: String)] = []
        for (id, result) in document.results where result.state == .evaluating {
            guard let node = graph.nodes[id] else { continue }
            named.append((NodeShape(node, in: graph, registry: registry).title, id.rawValue.uuidString))
        }
        named.sort { $0.title == $1.title ? $0.id < $1.id : $0.title < $1.title }
        return named.map(\.title)
    }

    /// Follows the document's evaluating nodes into `slowEvaluation`, once; the first change schedules one update, which follows
    /// again. A registration made for a document since replaced is ignored by its generation.
    func followEvaluation() {
        evaluationObservationGeneration += 1
        let generation = evaluationObservationGeneration
        evaluationUpdatePending = false
        let names = withObservationTracking {
            evaluatingNodeNames()
        } onChange: { [weak self] in
            // Called as the property is about to change, on the actor that changes it; the update runs after the change.
            MainActor.assumeIsolated { self?.scheduleEvaluationFollow(generation) }
        }
        slowEvaluation.follow(names)
    }

    private func scheduleEvaluationFollow(_ generation: Int) {
        guard generation == evaluationObservationGeneration, !evaluationUpdatePending else { return }
        evaluationUpdatePending = true
        Task { [weak self] in self?.followEvaluation() }
    }
}

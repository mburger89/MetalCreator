import CreatorKernel
import Foundation
import Observation

/// One open document: the graph, its undo history and its latest evaluation. The UI observes
/// this. Every edit goes through `perform(_:coalescingKey:)`.
@MainActor
@Observable
public final class DocumentModel {
    public private(set) var graph: Graph
    public private(set) var results: [NodeID: NodeResult] = [:]
    /// The last successful outputs of each node. The viewport ghosts these when a node errors (spec §4.4).
    public private(set) var lastGoodOutputs: [NodeID: [SocketName: Value]] = [:]
    public private(set) var isEvaluating = false
    public var viewState: ViewState

    /// The node shown in "Selected node" preview mode. It joins the evaluation demand.
    public var previewNode: NodeID? = nil {
        didSet {
            if oldValue != previewNode { scheduleEvaluation() }
        }
    }

    public let registry: NodeRegistry
    private var undoStack = UndoStack()
    @ObservationIgnored private let evaluator: Evaluator
    @ObservationIgnored private var evaluationTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init(file: GraphFile = GraphFile(), registry: NodeRegistry, kernel: any Kernel,
                cacheBudgetBytes: Int = 512 * 1024 * 1024) {
        self.graph = file.graph
        self.viewState = file.viewState
        self.registry = registry
        self.evaluator = Evaluator(registry: registry, kernel: kernel, cacheBudgetBytes: cacheBudgetBytes)
        scheduleEvaluation()
    }

    public convenience init(data: Data, registry: NodeRegistry, kernel: any Kernel) throws {
        self.init(file: try GraphFileIO.decode(data, registry: registry), registry: registry, kernel: kernel)
    }

    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }

    /// Applies an edit. Pass the same `coalescingKey` for every step of a slider or handle
    /// drag, then call `endCoalescing()` when the drag ends, so the drag is one undo step.
    public func perform(_ command: GraphCommand, coalescingKey: String? = nil) throws(GraphError) {
        // The stale set must be taken before the edit, so dependents of removed nodes and links count.
        let stale = graph.downstreamClosure(of: command.touchedNodes)
        let inverse = try graph.apply(command, registry: registry)
        undoStack.record(forward: command, inverse: inverse, coalescingKey: coalescingKey)
        didChange(markingStale: stale)
    }

    public func endCoalescing() {
        undoStack.endCoalescing()
    }

    public func undo() {
        guard let entry = undoStack.takeUndo() else { return }
        replay(entry.inverse)
    }

    public func redo() {
        guard let entry = undoStack.takeRedo() else { return }
        replay(entry.forward)
    }

    public func fileData() throws -> Data {
        try GraphFileIO.encode(GraphFile(graph: graph, viewState: viewState))
    }

    /// Returns once the most recently scheduled evaluation has finished and been applied.
    public func waitForEvaluation() async {
        while let task = evaluationTask {
            await task.value
            if evaluationTask == task { return }
        }
    }

    // MARK: - Evaluation

    private var demand: Set<NodeID> {
        var ids = Set(graph.nodes.values.filter(\.isOutput).map(\.id))
        if let previewNode { ids.insert(previewNode) }
        return ids
    }

    private func replay(_ command: GraphCommand) {
        let stale = graph.downstreamClosure(of: command.touchedNodes)
        do {
            try graph.apply(command, registry: registry)
        } catch {
            // Undo and redo replay commands that were valid when recorded, so this means
            // the history is out of step with the graph.
            assertionFailure("Undo history could not be replayed: \(error)")
        }
        didChange(markingStale: stale)
    }

    private func didChange(markingStale stale: Set<NodeID>) {
        let existing = Set(graph.nodes.keys)
        results = results.filter { existing.contains($0.key) }
        lastGoodOutputs = lastGoodOutputs.filter { existing.contains($0.key) }
        for id in stale where results[id] != nil {
            results[id]?.state = .evaluating
        }
        if let previewNode, !existing.contains(previewNode) {
            self.previewNode = nil  // didSet schedules the evaluation
        } else {
            scheduleEvaluation()
        }
    }

    private func scheduleEvaluation() {
        evaluationTask?.cancel()
        generation += 1
        let current = generation
        let snapshot = graph
        let demand = demand
        let evaluator = evaluator
        isEvaluating = true
        evaluationTask = Task {
            let report: EvaluationReport
            do {
                report = try await evaluator.evaluate(snapshot, demand: demand)
            } catch {
                return  // Cancelled: a newer generation is already scheduled.
            }
            guard current == self.generation else { return }
            self.apply(report)
        }
    }

    private func apply(_ report: EvaluationReport) {
        for (id, result) in report.results {
            results[id] = result
            if result.state.isSuccess, let outputs = result.outputs {
                lastGoodOutputs[id] = outputs
            }
        }
        isEvaluating = false
    }
}

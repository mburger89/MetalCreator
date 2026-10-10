import CreatorKernel
import Foundation
import Observation

/// One open document: the graph and its group definitions, its undo history and its latest evaluation. The UI
/// observes this. Every edit goes through `perform(_:coalescingKey:)` (or `perform(_:at:coalescingKey:)`).
@MainActor
@Observable
public final class DocumentModel {
    /// The top-level graph and the group definitions (groups spec §4), edited together.
    public private(set) var content: GraphContent
    public private(set) var results: [NodeID: NodeResult] = [:]
    /// Results inside group nodes (groups spec §5), by instance path: the group nodes from the top level down, then
    /// the inner node's ID (`EvaluationReport.innerResults`). C2 draws a group's inside from these.
    public private(set) var innerResults: [[NodeID]: NodeResult] = [:]
    /// The last successful outputs of each node. The viewport ghosts these when a node errors (spec §4.4).
    public private(set) var lastGoodOutputs: [NodeID: [SocketName: Value]] = [:]
    public private(set) var isEvaluating = false
    /// Editor state saved with the file. A non-finite zoom, offset or camera is refused (the previous
    /// value is kept), so the document can always be saved (JSON has no NaN).
    public var viewState: ViewState {
        didSet {
            if !viewState.canvasZoom.isFinite { viewState.canvasZoom = oldValue.canvasZoom }
            if !viewState.canvasOffset.isFinite { viewState.canvasOffset = oldValue.canvasOffset }
            if let camera = viewState.camera, !camera.isFinite { viewState.camera = oldValue.camera }
            if let home = viewState.homeCamera, !home.isFinite { viewState.homeCamera = oldValue.homeCamera }
        }
    }

    /// The node shown in "Selected node" preview mode. It joins the evaluation demand.
    public var previewNode: NodeID? {
        didSet {
            if oldValue != previewNode { scheduleEvaluation() }
        }
    }

    /// The level the graph panel shows (groups spec §6): the group nodes entered from the top level, each by its ID in
    /// the graph before it; empty on the top level. Everything on that level is evaluated, so `innerResults` has
    /// a state for each of its nodes.
    public var inspectedLevel: [NodeID] = [] {
        didSet {
            if oldValue != inspectedLevel { scheduleEvaluation() }
        }
    }

    /// The registry the document was opened with, without its definitions.
    @ObservationIgnored private let baseRegistry: NodeRegistry
    private var undoStack = UndoStack()
    @ObservationIgnored private let evaluator: Evaluator
    @ObservationIgnored private var evaluationTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init(file: GraphFile = GraphFile(), registry: NodeRegistry, kernel: any Kernel,
                cacheBudgetBytes: Int = 512 * 1024 * 1024) {
        self.content = GraphContent(graph: file.graph, definitions: file.definitions)
        self.viewState = file.viewState
        self.baseRegistry = registry
        self.evaluator = Evaluator(registry: registry, kernel: kernel, cacheBudgetBytes: cacheBudgetBytes)
        scheduleEvaluation()
    }

    public convenience init(data: Data, registry: NodeRegistry, kernel: any Kernel) throws {
        self.init(file: try GraphFileIO.decode(data, registry: registry), registry: registry, kernel: kernel)
    }

    /// The top-level graph.
    public var graph: Graph { content.graph }
    /// The document's group definitions.
    public var definitions: [GroupID: GroupDefinition] { content.definitions }
    /// The registry carrying this document's definitions, so group nodes have their sockets.
    public var registry: NodeRegistry { baseRegistry.withGroups(content.definitions) }

    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }
    /// The name of the step Undo would take back ("Add Note"), or `nil` with nothing to undo.
    public var undoName: String? { undoStack.undoName }
    /// The name of the step Redo would re-apply, or `nil` with nothing to redo.
    public var redoName: String? { undoStack.redoName }

    /// Applies an edit. Pass the same `coalescingKey` for every step of a slider or handle
    /// drag, then call `endCoalescing()` when the drag ends, so the drag is one undo step. `name` is the step's name in
    /// the Edit menu (`UndoName`); without one (or with a blank one) the step is called "Edit", so
    /// every caller passes one. A coalesced run keeps the name of its first record.
    public func perform(_ command: GraphCommand, coalescingKey: String? = nil, name: String? = nil) throws(GraphError) {
        // The stale set must be taken before the edit, so dependents of removed nodes and links count.
        let stale = graph.downstreamClosure(of: content.touchedTopLevelNodes(command))
        let effect = effect(of: command)
        let inverse = try content.apply(command, registry: baseRegistry)
        undoStack.record(forward: command, inverse: inverse, coalescingKey: coalescingKey,
                         name: UndoName.cleaned(name) ?? UndoName.edit)
        didChange(effect, markingStale: stale)
    }

    /// Applies a graph command to the graph at `path`: the top level, or inside a group definition (groups spec §5).
    public func perform(_ command: GraphCommand, at path: GraphPath, coalescingKey: String? = nil,
                        name: String? = nil) throws(GraphError) {
        try perform(command.at(path), coalescingKey: coalescingKey, name: name)
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
        try GraphFileIO.encode(GraphFile(graph: graph, definitions: definitions, viewState: viewState))
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

    /// What applying `command` to the content as it is now changes: results (mark the stale nodes and re-evaluate),
    /// only group messages (re-evaluate, every result cached, nothing marked), or nothing.
    private func effect(of command: GraphCommand) -> (results: Bool, messages: Bool) {
        (content.affectsResults(command), content.affectsMessages(command))
    }

    private func replay(_ command: GraphCommand) {
        let stale = graph.downstreamClosure(of: content.touchedTopLevelNodes(command))
        let effect = effect(of: command)
        do {
            try content.apply(command, registry: baseRegistry)
        } catch {
            // Undo and redo replay commands that were valid when recorded, so this means
            // the history is out of step with the graph.
            assertionFailure("Undo history could not be replayed: \(error)")
        }
        didChange(effect, markingStale: stale)
    }

    private func didChange(_ effect: (results: Bool, messages: Bool), markingStale stale: Set<NodeID>) {
        guard effect.results else {
            // A renamed definition or inner node: group messages carry the names, so re-evaluate (from the cache).
            if effect.messages { scheduleEvaluation() }
            return
        }
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
        let snapshot = content
        let demand = demand
        let level = inspectedLevel
        let evaluator = evaluator
        isEvaluating = true
        evaluationTask = Task {
            let report: EvaluationReport
            do {
                report = try await evaluator.evaluate(snapshot.graph, definitions: snapshot.definitions, demand: demand,
                                                inspecting: level)
            } catch {
                return  // Cancelled: a newer generation is already scheduled.
            }
            guard current == self.generation else { return }
            self.apply(report)
        }
    }

    private func apply(_ report: EvaluationReport) {
        // Replace, not merge: a node that left the demand must not keep a stale `.evaluating` state.
        results = report.results
        innerResults = report.innerResults
        for (id, result) in report.results {
            if result.state.isSuccess, let outputs = result.outputs {
                lastGoodOutputs[id] = outputs
            }
        }
        isEvaluating = false
    }
}

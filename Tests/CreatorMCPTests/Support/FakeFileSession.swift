import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorMCP
import Foundation

/// Forwards everything to a `DocumentModelSession` and records the file calls, answering them with `outcome`.
@MainActor final class FakeFileSession: DocumentSession {
    enum Call: Equatable {
        case new(discard: Bool)
        case open(URL, discard: Bool)
        case save(URL?, overwrite: Bool)
        case export(String, URL, overwrite: Bool)
    }

    let base: DocumentModelSession
    var calls: [Call] = []
    var outcome: SessionOutcome = .done(nil)
    /// Progress reported by `export` before it answers.
    var exportProgress: [Double] = []

    init(base: DocumentModelSession) { self.base = base }

    var content: GraphContent { base.content }
    var registry: NodeRegistry { base.registry }
    var results: [NodeID: NodeResult] { base.results }
    var units: DocumentUnits { base.units }
    var displayName: String { base.displayName }
    var isEdited: Bool { base.isEdited }
    var fileURL: URL? { base.fileURL }

    func outputSummary(of node: NodeID, socket: SocketName) -> String? { base.outputSummary(of: node, socket: socket) }
    func editRefusal() -> String? { base.editRefusal() }
    func perform(_ command: GraphCommand, name: String) throws(GraphError) { try base.perform(command, name: name) }
    func freePosition(for node: Node, in graph: Graph) -> Vector2 { base.freePosition(for: node, in: graph) }
    func settle(within limit: Duration) async -> Bool { await base.settle(within: limit) }
    func undoClientStep() -> SessionOutcome { base.undoClientStep() }
    func redoClientStep() -> SessionOutcome { base.redoClientStep() }
    func setFile(_ url: URL, on node: NodeID, embed: Bool) async -> SessionOutcome { await base.setFile(url, on: node, embed: embed) }

    func newDocument(discardUnsaved: Bool) -> SessionOutcome {
        calls.append(.new(discard: discardUnsaved))
        return outcome
    }

    func open(_ url: URL, discardUnsaved: Bool) -> SessionOutcome {
        calls.append(.open(url, discard: discardUnsaved))
        return outcome
    }

    func save(to url: URL?, overwrite: Bool) -> SessionOutcome {
        calls.append(.save(url, overwrite: overwrite))
        return outcome
    }

    func export(_ kind: String, to url: URL, overwrite: Bool, progress: MCPCallContext) async -> SessionOutcome {
        calls.append(.export(kind, url, overwrite: overwrite))
        for (index, value) in exportProgress.enumerated() { progress.progress?(value, 1, "Step \(index + 1)") }
        return outcome
    }
}

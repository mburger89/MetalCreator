import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// How a session call that can be refused ended: done (with a sentence to relay, if any) or refused in words.
public enum SessionOutcome: Sendable, Equatable {
    case done(String?)
    case refused(String)
}

/// The document the server drives. Every member runs on the main actor; the app supplies one over its model, tests another.
@MainActor public protocol DocumentSession: AnyObject {
    var content: GraphContent { get }
    var registry: NodeRegistry { get }
    var results: [NodeID: NodeResult] { get }
    var units: DocumentUnits { get }
    /// The file's name, or "Untitled".
    var displayName: String { get }
    var isEdited: Bool { get }
    var fileURL: URL? { get }

    /// One line for an output socket's value (a field's recipe, "3 solids", "number 12.5"), or nil when it has none yet.
    func outputSummary(of node: NodeID, socket: SocketName) -> String?
    /// nil when an edit may run now; else the sentence saying why not (a sketch is open, a pick is running).
    func editRefusal() -> String?
    /// Applies the step a client made: one undo step, named `name`, never coalesced.
    func perform(_ command: GraphCommand, name: String) throws(GraphError)
    /// Where a new node goes on the canvas.
    /// `graph` is the graph to keep clear of (a batch passes its scratch copy, which holds the nodes it has added so far).
    func freePosition(for node: Node, in graph: Graph) -> Vector2
    /// Waits for the evaluation; false when `limit` passed first.
    func settle(within limit: Duration) async -> Bool
    func undoClientStep() -> SessionOutcome
    func redoClientStep() -> SessionOutcome
    func newDocument(discardUnsaved: Bool) -> SessionOutcome
    func open(_ url: URL, discardUnsaved: Bool) -> SessionOutcome
    func save(to url: URL?, overwrite: Bool) -> SessionOutcome
    func export(_ kind: String, to url: URL, overwrite: Bool, progress: MCPCallContext) async -> SessionOutcome
    func setFile(_ url: URL, on node: NodeID, embed: Bool) async -> SessionOutcome
}

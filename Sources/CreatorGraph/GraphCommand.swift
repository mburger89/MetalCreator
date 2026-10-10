import CreatorGeometry
import CreatorKernel

/// Every edit to a graph. Applying one returns its inverse (spec §4.5).
public indirect enum GraphCommand: Sendable, Equatable {
    case addNode(Node)
    case removeNode(NodeID)
    /// Re-inserts a removed node together with the links that were removed with it.
    case restoreNode(Node, links: [Link])
    /// Connects, replacing any wire already in `link.to`.
    case connect(Link)
    case disconnect(Link)
    /// Re-inserts wires exactly as they were removed. Unlike `connect`, it does no validation
    /// (undo must restore what was there, even if a node type is no longer registered), and it
    /// only refuses a wire that is already present.
    case restoreLinks([Link])
    /// Sets (or with `nil`, clears) a stored input constant or setting.
    case setInput(NodeID, SocketName, ConstantValue?)
    case move(NodeID, to: Vector2)
    case rename(NodeID, String)
    case setOutput(NodeID, Bool)
    case addParameter(GraphParameter)
    case removeParameter(ParameterID)
    case setParameter(ParameterID, ConstantValue)
    case batch([GraphCommand])
    /// A graph command applied inside definition `GroupID` (groups spec §5). Group commands run only through
    /// `GraphContent.apply`; `Graph.apply` refuses them.
    case inDefinition(GroupID, GraphCommand)
    /// Adds a sticky note, or replaces the one with its ID whole (canvas comments spec 2026-10-09 §7): a move, a
    /// resize and an edit are each one of these carrying the note's new value. Never affects evaluation.
    case setSticky(StickyNote)
    case removeSticky(CommentID)
    /// Adds a comment frame, or replaces the one with its ID whole; the frame counterpart of `setSticky`.
    case setFrame(CommentFrame)
    case removeFrame(CommentID)
    /// Adds a group definition (the inverse of `removeDefinition`).
    case addDefinition(GroupDefinition)
    /// Removes a definition that no group node uses.
    case removeDefinition(GroupID)
    /// Replaces a definition's name, accent and sockets; wires and values on its group nodes are separate commands.
    case setInterface(GroupID, GroupInterface)

    /// Nodes whose own inputs or existence change, on the graph the command addresses (group commands touch none
    /// here; `GraphContent.touchedTopLevelNodes` adds the group nodes they reach). Callers that mark results stale
    /// must take `downstreamClosure` on the graph *before* applying the command, so dependents of removed
    /// nodes and links are included.
    public var touchedNodes: Set<NodeID> {
        switch self {
        case .addNode(let node): [node.id]
        case .restoreNode(let node, let links): Set(links.map(\.to.node)).union([node.id])
        case .removeNode(let id), .setInput(let id, _, _), .setOutput(let id, _): [id]
        case .connect(let link), .disconnect(let link): [link.to.node]
        case .restoreLinks(let links): Set(links.map(\.to.node))
        case .move, .rename, .addParameter, .removeParameter, .setParameter: []
        case .setSticky, .removeSticky, .setFrame, .removeFrame: []
        case .inDefinition, .addDefinition, .removeDefinition, .setInterface: []
        case .batch(let commands): commands.reduce(into: []) { $0.formUnion($1.touchedNodes) }
        }
    }

    /// False for edits that can't change any node's result (moving or renaming), so callers
    /// need not re-evaluate.
    public var affectsResults: Bool {
        switch self {
        case .move, .rename, .addDefinition, .removeDefinition: false
        case .setSticky, .removeSticky, .setFrame, .removeFrame: false
        case .batch(let commands): commands.contains { $0.affectsResults }
        case .inDefinition(_, let command): command.affectsResults
        default: true
        }
    }
}

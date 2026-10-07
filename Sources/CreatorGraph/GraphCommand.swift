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

    /// Nodes whose own inputs or existence change. Callers that mark results stale must take
    /// `downstreamClosure` on the graph *before* applying the command, so dependents of removed
    /// nodes and links are included.
    public var touchedNodes: Set<NodeID> {
        switch self {
        case .addNode(let node): [node.id]
        case .restoreNode(let node, let links): Set(links.map(\.to.node)).union([node.id])
        case .removeNode(let id), .setInput(let id, _, _), .setOutput(let id, _): [id]
        case .connect(let link), .disconnect(let link): [link.to.node]
        case .restoreLinks(let links): Set(links.map(\.to.node))
        case .move, .rename, .addParameter, .removeParameter, .setParameter: []
        case .batch(let commands): commands.reduce(into: []) { $0.formUnion($1.touchedNodes) }
        }
    }

    /// False for edits that can't change any node's result (moving or renaming), so callers
    /// need not re-evaluate.
    public var affectsResults: Bool {
        switch self {
        case .move, .rename: false
        case .batch(let commands): commands.contains { $0.affectsResults }
        default: true
        }
    }
}

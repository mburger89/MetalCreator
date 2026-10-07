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
    /// Sets (or with `nil`, clears) a stored input constant or setting.
    case setInput(NodeID, SocketName, ConstantValue?)
    case move(NodeID, to: Vector2)
    case rename(NodeID, String)
    case setOutput(NodeID, Bool)
    case addParameter(GraphParameter)
    case removeParameter(ParameterID)
    case setParameter(ParameterID, ConstantValue)
    case batch([GraphCommand])

    /// Nodes whose results this command can change (for marking them `.evaluating`).
    public var touchedNodes: Set<NodeID> {
        switch self {
        case .addNode(let node), .restoreNode(let node, _): [node.id]
        case .removeNode(let id), .setInput(let id, _, _), .setOutput(let id, _): [id]
        case .connect(let link), .disconnect(let link): [link.to.node]
        case .move, .rename, .addParameter, .removeParameter, .setParameter: []
        case .batch(let commands): commands.reduce(into: []) { $0.formUnion($1.touchedNodes) }
        }
    }
}

import CreatorGraph
import CreatorKernel
import Foundation

/// A tool's refusal, in a sentence the client can read.
public struct Refusal: Error, Equatable, Sendable {
    public let sentence: String

    public init(_ sentence: String) { self.sentence = sentence }
}

/// How a client names a node and a socket: a node by its full ID or a unique name, a socket as "Node.socket".
public enum Addressing {
    /// The node `ref` names: a full UUID, else a name that exactly one node has.
    public static func node(_ ref: JSONValue?, in graph: Graph) -> Result<NodeID, Refusal> {
        guard let text = ref?.string, !text.isEmpty else { return .failure(Refusal("Say which node, by its ID or name.")) }
        if let uuid = UUID(uuidString: text) {
            let id = NodeID(rawValue: uuid)
            return graph.nodes[id] != nil ? .success(id) : .failure(Refusal("There's no node with ID \(text)."))
        }
        let matches = graph.nodes.values.filter { $0.name == text }
        switch matches.count {
        case 0: return .failure(Refusal("There's no node called “\(text)”."))
        case 1: return .success(matches[0].id)
        default: return .failure(Refusal("Two nodes are called “\(text)”; use the node's ID."))
        }
    }

    /// "Node.socket" (split at the last dot, so a node name may hold dots), checked against the node's own sockets.
    public static func endpoint(
        _ text: String, in graph: Graph, registry: NodeRegistry, output: Bool
    ) -> Result<Endpoint, Refusal> {
        guard let dot = text.lastIndex(of: "."), dot != text.startIndex, text.index(after: dot) != text.endIndex else {
            return .failure(Refusal("“\(text)” should read node.socket."))
        }
        let nodePart = String(text[..<dot])
        let socket = String(text[text.index(after: dot)...])
        switch node(.string(nodePart), in: graph) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let id):
            guard let found = graph.nodes[id] else { return .failure(Refusal("There's no node with ID \(id.rawValue.uuidString).")) }
            let sockets = output ? registry.outputs(for: found) : registry.inputs(for: found)
            guard sockets.contains(where: { $0.name.rawValue == socket }) else {
                return .failure(Refusal("\(found.name) has no \(output ? "output" : "input") called “\(socket)”."))
            }
            return .success(Endpoint(node: id, socket: SocketName(socket)))
        }
    }
}

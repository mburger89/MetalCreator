import CreatorGraph
import CreatorKernel

/// What the canvas needs to draw and hit-test one node: its title, category and sockets. A registered node's sockets
/// are `registry.inputs(for:)`/`outputs(for:)`, so per-node sockets (the Sketch node's exposed dimensions, a group
/// node's definition sockets) are drawn and wired.
/// A node whose type isn't registered is a "missing node" (spec §4.5): it keeps the sockets its
/// wires name, untyped.
public struct NodeShape: Equatable, Sendable {
    public struct Socket: Equatable, Sendable {
        public var name: SocketName
        /// `nil` for a missing node's sockets.
        public var type: SocketType?
    }

    public var title: String
    public var category: NodeCategory
    public var inputs: [Socket]
    public var outputs: [Socket]
    public var isMissing: Bool
    /// A group node, Group Input or Group Output: the accent of its definition, which colours its header.
    public var accent: AccentRole?
    /// A group node: drawn with a doubled border (groups spec §6).
    public var isGroup: Bool

    public init(title: String, category: NodeCategory, inputs: [Socket], outputs: [Socket], isMissing: Bool = false,
                accent: AccentRole? = nil, isGroup: Bool = false) {
        self.title = title
        self.category = category
        self.inputs = inputs
        self.outputs = outputs
        self.isMissing = isMissing
        self.accent = accent
        self.isGroup = isGroup
    }

    public init(_ node: Node, in graph: Graph, registry: NodeRegistry) {
        if let definition = registry[node.typeID] {
            var inputs = registry.inputs(for: node).map { Socket(name: $0.name, type: $0.type) }
            var outputs = registry.outputs(for: node).map { Socket(name: $0.name, type: $0.type) }
            // Group Output ends with a "+" input to drop a wire on, Group Input with a "+" output to drag from
            // (groups spec §6): exposing a new socket.
            let plus = Socket(name: GroupNaming.plusSocket, type: nil)
            if node.typeID == GroupNodes.outputTypeID { inputs.append(plus) }
            if node.typeID == GroupNodes.inputTypeID { outputs.append(plus) }
            let group = GroupNodes.typeIDs.contains(node.typeID) ? registry.group(of: node) : nil
            let isGroup = node.typeID == GroupNodes.groupTypeID
            self.init(title: isGroup ? group?.name ?? node.name : node.name, category: definition.category,
                      inputs: inputs, outputs: outputs, accent: group?.accent, isGroup: isGroup)
        } else {
            let inputs = Set(graph.links.filter { $0.to.node == node.id }.map(\.to.socket)).sorted()
            let outputs = Set(graph.links.filter { $0.from.node == node.id }.map(\.from.socket)).sorted()
            self.init(title: node.name, category: .value,
                      inputs: inputs.map { Socket(name: $0, type: nil) },
                      outputs: outputs.map { Socket(name: $0, type: nil) }, isMissing: true)
        }
    }
}

/// A reusable sub-graph (groups spec §4): every group node naming it stands for its `graph`, with Group Input
/// standing for the node's inputs and Group Output for its outputs. Editing it updates every instance.
public struct GroupDefinition: Sendable, Equatable {
    public let id: GroupID
    /// Unique in the document, for example "Rib".
    public var name: String
    public var accent: AccentRole
    public var inputs: [SocketSpec]
    public var outputs: [SocketSpec]
    /// The inside: its nodes (exactly one Group Input and one Group Output among them) and links.
    public var graph: Graph

    public init(id: GroupID = GroupID(), name: String, accent: AccentRole = .purple, inputs: [SocketSpec] = [],
                outputs: [SocketSpec] = [], graph: Graph = Graph()) {
        self.id = id
        self.name = name
        self.accent = accent
        self.inputs = inputs
        self.outputs = outputs
        self.graph = graph
    }

    /// Name, accent and sockets: what `GraphCommand.setInterface` replaces.
    public var interface: GroupInterface {
        get { GroupInterface(name: name, accent: accent, inputs: inputs, outputs: outputs) }
        set {
            name = newValue.name
            accent = newValue.accent
            inputs = newValue.inputs
            outputs = newValue.outputs
        }
    }

    /// The Group Input node (the lowest ID if a hand-edited file has several).
    public var inputNode: Node? { boundaryNode(GroupNodes.inputTypeID) }

    /// The Group Output node (the lowest ID if a hand-edited file has several).
    public var outputNode: Node? { boundaryNode(GroupNodes.outputTypeID) }

    private func boundaryNode(_ typeID: String) -> Node? {
        graph.nodes.values.filter { $0.typeID == typeID }.min { $0.id < $1.id }
    }
}

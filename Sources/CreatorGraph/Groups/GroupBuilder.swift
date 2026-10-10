import CreatorGeometry
import CreatorKernel

/// Builds what one Group command makes (`GroupCommands.group`): the new definition, holding the grouped nodes at
/// their places relative to the selection's top-left and the links among them, and the wires outside that join the
/// new group node to the rest of its graph.
struct GroupBuilder {
    private let graph: Graph
    private let sockets: NodeRegistry
    private let input: NodeID
    private let output: NodeID
    let groupNode: Node
    private(set) var definition: GroupDefinition
    private(set) var outside: [Link] = []
    private var inputs: [Endpoint: SocketName] = [:]
    private var outputs: [Endpoint: SocketName] = [:]

    /// `sockets` carries the document's definitions; `registry` makes the new nodes.
    init(_ picked: [Node], from graph: Graph, content: GraphContent, sockets: NodeRegistry,
         registry: NodeRegistry) throws(GraphError) {
        let topLeft = Vector2(picked.map(\.position.x).min() ?? 0, picked.map(\.position.y).min() ?? 0)
        let right = (picked.map(\.position.x).max() ?? 0) - topLeft.x
        let id = GroupID()
        var definition = GroupDefinition.make(
            id: id, name: GroupNaming.uniqueDefinitionName("Group", among: content.definitions), registry: registry,
            inputAt: Vector2(-GroupCommands.boundaryMargin, 0), outputAt: Vector2(right + GroupCommands.boundaryMargin, 0))
        guard let input = definition.inputNode, let output = definition.outputNode else { throw GroupRefusal.boundaryCount }
        let ids = Set(picked.map(\.id))
        for node in picked {
            var moved = node
            moved.position = node.position - topLeft
            definition.graph.nodes[moved.id] = moved
        }
        definition.graph.links = graph.links.filter { ids.contains($0.from.node) && ids.contains($0.to.node) }
        self.graph = graph
        self.sockets = sockets
        self.input = input.id
        self.output = output.id
        self.definition = definition
        groupNode = sockets.withGroups(content.definitions.merging([id: definition]) { first, _ in first })
            .makeGroupNode(GroupNodes.groupTypeID, for: id, at: topLeft)
    }

    /// A wire from outside into the selection: its source becomes an input (once per source), and inside, Group
    /// Input feeds the wire's target.
    mutating func wireIn(_ link: Link) throws(GraphError) {
        let name: SocketName
        if let known = inputs[link.from] {
            name = known
        } else {
            guard let type = type(of: link.from) else {
                throw .invalidValue("A wire into the selection comes from a socket of unknown type, so it can't become an input.")
            }
            let target = graph.nodes[link.to.node].flatMap { node in
                sockets.inputs(for: node).first { $0.name == link.to.socket }
            }
            name = GroupNaming.uniqueSocketName(link.to.socket, among: definition.inputs.map(\.name))
            // As `GroupCommands.exposeInput` does for the "+" drop, so unwiring the source later leaves the part as it was.
            definition.inputs.append(SocketSpec(name, type, access: target?.access ?? .item, defaultValue: target?.defaultValue,
                                                unit: target?.unit ?? .none, range: target?.range,
                                                optional: target?.isOptional ?? false))
            inputs[link.from] = name
            outside.append(Link(from: link.from, to: Endpoint(node: groupNode.id, socket: name)))
        }
        definition.graph.links.append(Link(from: Endpoint(node: input, socket: name), to: link.to))
    }

    /// A wire from the selection out: its source becomes an output (once per source) that Group Output takes inside,
    /// and outside, the group node feeds the wire's target.
    mutating func wireOut(_ link: Link) throws(GraphError) {
        let name: SocketName
        if let known = outputs[link.from] {
            name = known
        } else {
            guard let type = type(of: link.from) else {
                throw .invalidValue("A wire out of the selection leaves a socket of unknown type, so it can't become an output.")
            }
            name = GroupNaming.uniqueSocketName(link.from.socket, among: definition.outputs.map(\.name))
            definition.outputs.append(SocketSpec(name, type))
            outputs[link.from] = name
            definition.graph.links.append(Link(from: link.from, to: Endpoint(node: output, socket: name)))
        }
        outside.append(Link(from: Endpoint(node: groupNode.id, socket: name), to: link.to))
    }

    /// The definition with its links in canonical order.
    var finished: GroupDefinition {
        var finished = definition
        finished.graph.sortLinks()
        return finished
    }

    private func type(of source: Endpoint) -> SocketType? {
        graph.nodes[source.node].flatMap { node in sockets.outputs(for: node).first { $0.name == source.socket }?.type }
    }
}

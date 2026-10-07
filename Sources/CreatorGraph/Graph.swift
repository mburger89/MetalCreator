import CreatorKernel

/// The whole recipe: nodes, wires and document parameters. Pure data.
public struct Graph: Sendable, Equatable {
    public var nodes: [NodeID: Node]
    public var links: [Link]
    public var parameters: [GraphParameter]

    public init(nodes: [NodeID: Node] = [:], links: [Link] = [], parameters: [GraphParameter] = []) {
        self.nodes = nodes
        self.links = links
        self.parameters = parameters
    }
}

extension Graph: Codable {
    private enum CodingKeys: String, CodingKey { case nodes, links, parameters }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let list = try container.decode([Node].self, forKey: .nodes)
        nodes = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        links = try container.decodeIfPresent([Link].self, forKey: .links) ?? []
        parameters = try container.decodeIfPresent([GraphParameter].self, forKey: .parameters) ?? []
        sortLinks()  // Canonical order, so command + undo yields an equal graph.
    }

    /// Nodes are written as an array sorted by ID, so saved files diff cleanly.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodes.values.sorted { $0.id < $1.id }, forKey: .nodes)
        try container.encode(links, forKey: .links)
        try container.encode(parameters, forKey: .parameters)
    }
}

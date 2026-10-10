/// Saved in `GraphFile.definitions` (format 5). An accent this build doesn't know reads as purple, so a newer theme
/// role never stops a file from opening.
extension GroupDefinition: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, accent, inputs, outputs, graph }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(GroupID.self, forKey: .id),
                  name: try container.decode(String.self, forKey: .name),
                  accent: (try? container.decodeIfPresent(AccentRole.self, forKey: .accent)) ?? .purple,
                  inputs: try container.decodeIfPresent([SocketSpec].self, forKey: .inputs) ?? [],
                  outputs: try container.decodeIfPresent([SocketSpec].self, forKey: .outputs) ?? [],
                  graph: try container.decodeIfPresent(Graph.self, forKey: .graph) ?? Graph())
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(accent, forKey: .accent)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(outputs, forKey: .outputs)
        try container.encode(graph, forKey: .graph)
    }
}

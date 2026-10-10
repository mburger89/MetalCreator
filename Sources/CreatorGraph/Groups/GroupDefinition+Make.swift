import CreatorGeometry

extension GroupDefinition {
    /// Where `make` puts Group Input and Group Output when it isn't told.
    public static let defaultInputPosition = Vector2(-240, 0)
    public static let defaultOutputPosition = Vector2(240, 0)

    /// A definition whose inside holds only its Group Input and Group Output, both made by `registry.makeGroupNode`
    /// (so they carry this definition's ID in `NodeSetting.group`).
    public static func make(id: GroupID = GroupID(), name: String, accent: AccentRole = .purple, inputs: [SocketSpec] = [],
                            outputs: [SocketSpec] = [], registry: NodeRegistry,
                            inputAt: Vector2 = defaultInputPosition, outputAt: Vector2 = defaultOutputPosition) -> GroupDefinition {
        var definition = GroupDefinition(id: id, name: name, accent: accent, inputs: inputs, outputs: outputs)
        let input = registry.makeGroupNode(GroupNodes.inputTypeID, for: id, at: inputAt)
        let output = registry.makeGroupNode(GroupNodes.outputTypeID, for: id, at: outputAt)
        definition.graph.nodes[input.id] = input
        definition.graph.nodes[output.id] = output
        return definition
    }
}

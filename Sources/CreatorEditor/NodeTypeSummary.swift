import CreatorGraph

/// A node type in one line, its inputs → its outputs: "Extrude: profile, distance, mode, reversed → solid". The
/// node library shows it when a type is hovered.
public enum NodeTypeSummary {
    public static func text(_ definition: any NodeDefinition.Type) -> String {
        "\(definition.displayName): \(names(definition.inputs, none: "no inputs")) → \(names(definition.outputs, none: "no outputs"))"
    }

    private static func names(_ sockets: [SocketSpec], none: String) -> String {
        sockets.isEmpty ? none : sockets.map { InspectorLabel.text(for: $0.name).lowercased() }.joined(separator: ", ")
    }
}

import CreatorGraph

/// One line about a node type, built from its sockets (a type has no description text of its own).
public enum NodeDescriptions {
    public static func summary(of definition: any NodeDefinition.Type) -> String {
        func names(_ sockets: [SocketSpec]) -> String {
            sockets.isEmpty ? "none" : sockets.map(\.name.rawValue).joined(separator: ", ")
        }
        return "\(definition.displayName): inputs \(names(definition.inputs)) → outputs \(names(definition.outputs))"
    }
}

import CreatorGeometry

/// Maps type IDs to node definitions.
public struct NodeRegistry: Sendable {
    private let definitions: [String: any NodeDefinition.Type]

    /// Duplicate type IDs are a programming error and trap.
    public init(_ definitions: [any NodeDefinition.Type]) {
        var map: [String: any NodeDefinition.Type] = [:]
        for definition in definitions {
            precondition(map[definition.typeID] == nil, "Duplicate node typeID \(definition.typeID)")
            map[definition.typeID] = definition
        }
        self.definitions = map
    }

    public subscript(typeID: String) -> (any NodeDefinition.Type)? { definitions[typeID] }

    /// Every registered definition, sorted by display name.
    public var all: [any NodeDefinition.Type] { definitions.values.sorted { $0.displayName < $1.displayName } }

    /// A fresh node of a registered type. An unregistered type gives a node with version 1
    /// whose name is the type ID.
    public func makeNode(_ typeID: String, at position: Vector2 = .zero) -> Node {
        let definition = definitions[typeID]
        return Node(typeID: typeID, typeVersion: definition?.typeVersion ?? 1,
                    name: definition?.displayName ?? typeID, position: position)
    }
}

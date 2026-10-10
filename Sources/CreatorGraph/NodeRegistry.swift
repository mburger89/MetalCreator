import CreatorGeometry

/// Maps type IDs to node definitions. It always holds the three group types (`GroupNodes`), and carries the open
/// document's group definitions (`groups`), which give group nodes their sockets.
public struct NodeRegistry: Sendable {
    private let definitions: [String: any NodeDefinition.Type]
    /// The document's group definitions. Empty in a bare registry; `DocumentModel.registry` carries the document's
    /// (`withGroups(_:)`).
    public internal(set) var groups: [GroupID: GroupDefinition] = [:]

    /// Duplicate type IDs are a programming error and trap. The group types are added here, so a caller never lists them.
    public init(_ definitions: [any NodeDefinition.Type]) {
        var map: [String: any NodeDefinition.Type] = [:]
        for definition in definitions + GroupNodes.definitions {
            precondition(map[definition.typeID] == nil, "Duplicate node typeID \(definition.typeID)")
            map[definition.typeID] = definition
        }
        self.definitions = map
    }

    public subscript(typeID: String) -> (any NodeDefinition.Type)? { definitions[typeID] }

    /// Every definition the add-node palette and the library offer, sorted by display name: all but the group types,
    /// which are made by grouping (groups spec §5).
    public var all: [any NodeDefinition.Type] {
        definitions.values.filter { !GroupNodes.typeIDs.contains($0.typeID) }.sorted { $0.displayName < $1.displayName }
    }

    /// A fresh node of a registered type: named after it, seeded with its `defaultSettings`, and
    /// flagged `isOutput` when its category is `.output`, so Output nodes join the evaluation
    /// demand on every creation path (palette, app, tests). An unregistered type gives a plain
    /// node with version 1 whose name is the type ID.
    public func makeNode(_ typeID: String, at position: Vector2 = .zero) -> Node {
        let definition = definitions[typeID]
        return Node(typeID: typeID, typeVersion: definition?.typeVersion ?? 1,
                    name: definition?.displayName ?? typeID, inputValues: definition?.defaultSettings ?? [:],
                    position: position, isOutput: definition?.category == .output)
    }
}

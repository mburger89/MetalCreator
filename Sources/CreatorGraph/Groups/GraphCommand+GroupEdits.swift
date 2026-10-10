extension GraphCommand {
    /// The definitions this command gives a new interface (`.setInterface`), at any depth of its batches.
    var interfaceEdits: Set<GroupID> {
        switch self {
        case .setInterface(let id, _): [id]
        case .batch(let commands): commands.reduce(into: []) { $0.formUnion($1.interfaceEdits) }
        default: []
        }
    }

    /// Whether this command renames a node, at any depth of its batches.
    var renamesNodes: Bool {
        switch self {
        case .rename: true
        case .batch(let commands): commands.contains { $0.renamesNodes }
        default: false
        }
    }
}

import CreatorKernel

extension GraphContent {
    /// The top-level nodes whose own inputs or existence `command` changes: `GraphCommand.touchedNodes`, plus every
    /// top-level group node an edit inside a definition (or to its sockets) reaches. As with `touchedNodes`, take
    /// `graph.downstreamClosure` of it *before* applying the command.
    public func touchedTopLevelNodes(_ command: GraphCommand) -> Set<NodeID> {
        switch command {
        case .batch(let commands): commands.reduce(into: []) { $0.formUnion(touchedTopLevelNodes($1)) }
        case .inDefinition(let id, _), .setInterface(let id, _): GroupDependencies.dependents(of: id, in: self)
        case .addDefinition, .removeDefinition: []
        default: command.touchedNodes
        }
    }

    /// Whether `command` can change any node's result, judged against this content before it applies: as
    /// `GraphCommand.affectsResults`, except that a definition's new interface does only when its sockets change (a
    /// new name or accent changes no value).
    public func affectsResults(_ command: GraphCommand) -> Bool {
        switch command {
        case .batch(let commands): commands.contains { affectsResults($0) }
        case .setInterface(let id, let interface):
            definitions[id].map { $0.inputs != interface.inputs || $0.outputs != interface.outputs } ?? true
        default: command.affectsResults
        }
    }

    /// Whether `command` changes the text of a group node's message without changing any result: renaming a
    /// definition, or a node inside one, changes the trail inner messages carry ("Rib › Fillet: …", `GroupTrail`).
    public func affectsMessages(_ command: GraphCommand) -> Bool {
        switch command {
        case .batch(let commands): commands.contains { affectsMessages($0) }
        case .inDefinition(_, let inner): inner.renamesNodes
        case .setInterface(let id, let interface): definitions[id]?.name != interface.name
        default: false
        }
    }
}

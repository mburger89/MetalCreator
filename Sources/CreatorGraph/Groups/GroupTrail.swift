/// How an inner node's message reads on its group node (groups spec §5): "Rib › Fillet: …". A nested group's
/// message already starts with its own definition's name, so it gains only this one: "Rib › Hole pattern › Fillet: …".
enum GroupTrail {
    static func message(_ message: String, from inner: Node, in definition: GroupDefinition) -> String {
        inner.typeID == GroupNodes.groupTypeID
            ? "\(definition.name) › \(message)"
            : "\(definition.name) › \(inner.name): \(message)"
    }

    /// The first error inside, in evaluation order, as the group node's message.
    static func firstError(in level: EvaluationLevel, graph: Graph, definition: GroupDefinition) -> String? {
        for id in level.order {
            if case .error(let message)? = level.results[id]?.state, let node = graph.nodes[id] {
                return Self.message(message, from: node, in: definition)
            }
        }
        return nil
    }

    /// The first reason an inner node gave for waiting, in evaluation order.
    static func firstIdleReason(in level: EvaluationLevel, graph: Graph, definition: GroupDefinition) -> String? {
        for id in level.order {
            if case .idle(let reason?)? = level.results[id]?.state, let node = graph.nodes[id] {
                return Self.message(reason, from: node, in: definition)
            }
        }
        return nil
    }

    /// Every warning inside, one per line, each with its trail, in evaluation order and without repeats.
    static func warnings(in level: EvaluationLevel, graph: Graph, definition: GroupDefinition) -> [String] {
        var lines: [String] = []
        for id in level.order {
            guard case .warning(let text)? = level.results[id]?.state, let node = graph.nodes[id] else { continue }
            for line in text.split(separator: "\n") {
                let trailed = Self.message(String(line), from: node, in: definition)
                if !lines.contains(trailed) { lines.append(trailed) }
            }
        }
        return lines
    }
}

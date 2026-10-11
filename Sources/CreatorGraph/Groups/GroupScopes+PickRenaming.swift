import CreatorKernel

extension GroupScopes {
    /// How the picks of a graph name the nodes an edit moves: for every path from `graph` (`paths(in:definitions:)`)
    /// that `rename` maps to the path its node has after the edit, the identity before (`identity`) mapped to the one
    /// after, both reached through `chain` (the group nodes from the picks' graph down to `graph`). The copies a
    /// pattern node placed are named by the node and the tool together, so each renamed node of a type that places
    /// instances (`NodeDefinition.placesInstances`, found through `registry`) also renames its copies' identities to the
    /// ones its renamed pair makes (`lifting`), whatever tool they were made with that is in `graph`.
    static func names(in graph: Graph, definitions: [GroupID: GroupDefinition], through chain: [NodeID] = [],
                      registry: NodeRegistry, _ rename: ([NodeID]) -> [NodeID]?) -> [NodeID: NodeID] {
        var names: [NodeID: NodeID] = [:]
        var everything: [NodeID: NodeID] = [:]
        for path in paths(in: graph, definitions: definitions) {
            let before = identity(chain + path)
            let after = rename(path).map { identity(chain + $0) }
            if let after { names[before] = after }
            everything[before] = after ?? before
        }
        let placers = placerPaths(in: graph, definitions: definitions, registry: registry).map { identity(chain + $0) }
        let lifted = lifting(everything, placers: Set(placers)).filter { $0.key != $0.value }
        return names.merging(lifted) { first, _ in first }
    }

    /// Every graph that reaches the graph at `level`, with each chain of group nodes it reaches it through: `level`
    /// itself through no group node, and each graph placing it, directly or through other groups, once per chain.
    static func chains(to level: GraphPath, in content: GraphContent) -> [(path: GraphPath, chain: [NodeID])] {
        var found: [(path: GraphPath, chain: [NodeID])] = [(level, [])]
        guard case .definition(let target) = level else { return found }
        func visit(_ graph: Graph, from path: GraphPath, prefix: [NodeID], entered: [GroupID]) {
            for node in graph.nodes.values.sorted(by: { $0.id < $1.id }) where node.typeID == GroupNodes.groupTypeID {
                guard let id = node.inputValues[NodeSetting.group]?.groupID, !entered.contains(id),
                      let definition = content.definitions[id] else { continue }
                if id == target {
                    found.append((path, prefix + [node.id]))
                } else {
                    visit(definition.graph, from: path, prefix: prefix + [node.id], entered: entered + [id])
                }
            }
        }
        visit(content.graph, from: .root, prefix: [], entered: [])
        for definition in content.definitions.values.sorted(by: { $0.id < $1.id }) where definition.id != target {
            visit(definition.graph, from: .definition(definition.id), prefix: [], entered: [definition.id])
        }
        return found
    }

    /// The commands that keep every pick in `content` naming its faces when an edit to the graph at `level` changes
    /// the paths its nodes are reached by: `rename` maps a path from that graph to the node's path after the edit, or
    /// gives `nil` for one that stays. Each pick it changes gets one `setInput`, addressed to its graph; the picks on
    /// `skipping`, nodes of the graph at `level` that the edit takes out of it, are left as they are.
    static func renamingPicks(at level: GraphPath, in content: GraphContent, registry: NodeRegistry,
                              skipping: Set<NodeID> = [], _ rename: ([NodeID]) -> [NodeID]?) -> [GraphCommand] {
        guard let graph = content.graph(at: level) else { return [] }
        var commands: [GraphCommand] = []
        for (path, chain) in chains(to: level, in: content) {
            guard let host = content.graph(at: path) else { continue }
            let table = names(in: graph, definitions: content.definitions, through: chain, registry: registry, rename)
            guard !table.isEmpty else { continue }
            for node in host.nodes.values.sorted(by: { $0.id < $1.id }) where !(path == level && skipping.contains(node.id)) {
                for (setting, value) in node.inputValues.sorted(by: { $0.key < $1.key }) {
                    let renamed = value.renamingTags(table)
                    if renamed != value { commands.append(GraphCommand.setInput(node.id, setting, renamed).at(path)) }
                }
            }
        }
        return commands
    }
}

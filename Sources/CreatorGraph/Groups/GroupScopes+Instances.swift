import CreatorKernel

extension GroupScopes {
    /// Every path (as `paths(in:definitions:)` gives them) to a node whose type places instances
    /// (`NodeDefinition.placesInstances`): the ones whose copies' tags name a pair of nodes, the placer and the tool.
    static func placerPaths(in graph: Graph, definitions: [GroupID: GroupDefinition], registry: NodeRegistry,
                            entered: [GroupID] = []) -> [[NodeID]] {
        var found: [[NodeID]] = []
        for node in graph.nodes.values {
            if registry[node.typeID]?.placesInstances == true { found.append([node.id]) }
            guard node.typeID == GroupNodes.groupTypeID, let id = node.inputValues[NodeSetting.group]?.groupID,
                  !entered.contains(id), let definition = definitions[id] else { continue }
            found += placerPaths(in: definition.graph, definitions: definitions, registry: registry, entered: entered + [id])
                .map { [node.id] + $0 }
        }
        return found
    }

    /// `names` with the names of the copies the `placers` among its keys made (patterns spec §6): a copy's tags name
    /// the node that placed it and the tool's tag node (`NodeID.instanceScoped([placer, tool])`), so where `names`
    /// renames both, the copy's identity is renamed to the one the renamed pair makes. A placer or a tool that
    /// `names` doesn't rename leaves its copies as they are, which is right for a tool made outside the table's level.
    static func lifting(_ names: [NodeID: NodeID], placers: Set<NodeID>) -> [NodeID: NodeID] {
        var lifted = names
        for placer in placers {
            guard let renamedPlacer = names[placer] else { continue }
            for (tool, renamedTool) in names {
                lifted[NodeID.instanceScoped([placer, tool])] = NodeID.instanceScoped([renamedPlacer, renamedTool])
            }
        }
        return lifted
    }
}

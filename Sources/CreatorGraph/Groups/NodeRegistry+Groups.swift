import CreatorGeometry

extension NodeRegistry {
    /// This registry carrying `groups`, so group nodes, Group Inputs and Group Outputs have their definitions' sockets.
    public func withGroups(_ groups: [GroupID: GroupDefinition]) -> NodeRegistry {
        var copy = self
        copy.groups = groups
        return copy
    }

    /// The definition a group node, Group Input or Group Output belongs to, if `groups` has it.
    public func group(of node: Node) -> GroupDefinition? {
        node.inputValues[NodeSetting.group]?.groupID.flatMap { groups[$0] }
    }

    /// A node's input sockets. Every reader of a node's sockets (wiring, evaluation, the canvas, the inspector) asks
    /// here: a group node's are its definition's inputs, Group Output's are the definition's outputs (optional, so an
    /// unwired one is an output the group doesn't produce), and any other node's are `inputs(for:)` of its type.
    public func inputs(for node: Node) -> [SocketSpec] {
        switch node.typeID {
        case GroupNodes.groupTypeID:
            group(of: node)?.inputs ?? []
        case GroupNodes.inputTypeID:
            []
        case GroupNodes.outputTypeID:
            (group(of: node)?.outputs ?? []).map { spec in
                var optional = spec
                optional.isOptional = true
                return optional
            }
        default:
            self[node.typeID]?.inputs(for: node) ?? []
        }
    }

    /// A node's output sockets: a group node's are its definition's outputs, Group Input's are the definition's
    /// inputs, and any other node's are `outputs(for:)` of its type.
    public func outputs(for node: Node) -> [SocketSpec] {
        switch node.typeID {
        case GroupNodes.groupTypeID: group(of: node)?.outputs ?? []
        case GroupNodes.inputTypeID: group(of: node)?.inputs ?? []
        case GroupNodes.outputTypeID: []
        default: self[node.typeID]?.outputs(for: node) ?? []
        }
    }

    /// A group node, Group Input or Group Output of definition `group`, made by `makeNode` with `NodeSetting.group`
    /// set. A group node is named after its definition when `groups` has it.
    public func makeGroupNode(_ typeID: String, for group: GroupID, at position: Vector2 = .zero) -> Node {
        var node = makeNode(typeID, at: position)
        node.inputValues[NodeSetting.group] = .group(group)
        if typeID == GroupNodes.groupTypeID, let definition = groups[group] { node.name = definition.name }
        return node
    }
}

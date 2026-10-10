import CreatorKernel

/// Group definitions travelling with copied group nodes (groups spec §9): the clipboard carries every definition the
/// copied nodes use, and a paste merges them into the document by content.
public enum GroupMerge {
    /// What a paste does with the definitions it was carrying.
    public struct Plan: Sendable, Equatable {
        /// The definitions to add, innermost first, so each can be added once the ones it places exist.
        public var additions: [GroupDefinition] = []
        /// Each carried definition's ID in the document: the ID of the definition that has its content already (itself
        /// when the document has it as it is), itself when the document gains it as it is, else the ID of the copy
        /// added in its place.
        public var targets: [GroupID: GroupID] = [:]

        /// `node`, a pasted group node, pointing at the definition `targets` names.
        public func retargeting(_ node: Node) -> Node {
            guard node.typeID == GroupNodes.groupTypeID, let old = node.inputValues[NodeSetting.group]?.groupID,
                  let new = targets[old], new != old else { return node }
            var moved = node
            moved.inputValues[NodeSetting.group] = .group(new)
            return moved
        }
    }

    /// The definitions `nodes` need from `content`: those their group nodes name, and every one those place, however
    /// deep.
    public static func definitions(used nodes: [Node], in content: GraphContent) -> [GroupID: GroupDefinition] {
        var found: [GroupID: GroupDefinition] = [:]
        var pending = nodes.compactMap { node in
            node.typeID == GroupNodes.groupTypeID ? node.inputValues[NodeSetting.group]?.groupID : nil
        }
        while let id = pending.popLast() {
            guard found[id] == nil, let definition = content.definitions[id] else { continue }
            found[id] = definition
            pending += GroupDependencies.direct(definition.graph).sorted()
        }
        return found
    }

    /// How to merge `incoming` into `content`: a definition some definition of the document equals, ignoring ID and
    /// name (the same accent, sockets and inside, with nested group nodes retargeted), is reused, however the document
    /// came by it: the original, a rename of it, or a copy an earlier paste added. One the document has no match for
    /// is added as it is; one whose ID is taken by different content, or whose name is taken, is added as a copy
    /// named "Name (imported)" (made unique), with a new ID if the ID was taken. A definition that places a copied one
    /// is itself copied when that changed its content.
    public static func plan(importing incoming: [GroupID: GroupDefinition], into content: GraphContent) -> Plan {
        var plan = Plan()
        var names = Set(content.definitions.values.map(\.name))
        var visited: Set<GroupID> = []

        func resolve(_ id: GroupID) {
            guard let definition = incoming[id], visited.insert(id).inserted else { return }
            for placed in GroupDependencies.direct(definition.graph).sorted() { resolve(placed) }
            var merged = definition
            for (nodeID, node) in definition.graph.nodes { merged.graph.nodes[nodeID] = plan.retargeting(node) }
            // Looked for among the document's definitions and the copies this paste has added so far; the one with
            // the same ID wins, else the lowest ID.
            let same = (Array(content.definitions.values) + plan.additions).filter { hasSameContent($0, as: merged) }
            if let found = same.min(by: { ($0.id == id ? 0 : 1, $0.id) < ($1.id == id ? 0 : 1, $1.id) }) {
                plan.targets[id] = found.id
                return
            }
            let idTaken = content.definitions[id] != nil
            if idTaken || names.contains(merged.name) {
                merged.name = GroupNaming.uniqueName("\(merged.name) (imported)", taken: names)
            }
            let target = idTaken ? GroupID() : id
            if idTaken {
                merged = GroupDefinition(id: target, name: merged.name, accent: merged.accent, inputs: merged.inputs,
                                         outputs: merged.outputs, graph: merged.graph)
                for (nodeID, node) in merged.graph.nodes where GroupNodes.isBoundary(node) {
                    merged.graph.nodes[nodeID]?.inputValues[NodeSetting.group] = .group(target)
                }
            }
            names.insert(merged.name)
            plan.targets[id] = target
            plan.additions.append(merged)
        }
        for id in incoming.keys.sorted() { resolve(id) }
        return plan
    }

    /// Whether `a` and `b` differ at most in ID and name: the same accent, sockets and inside. Group Input and Group
    /// Output carry the ID of their own definition, so that is set aside.
    static func hasSameContent(_ a: GroupDefinition, as b: GroupDefinition) -> Bool {
        a.accent == b.accent && a.inputs == b.inputs && a.outputs == b.outputs
            && inside(a, ownedBy: a.id) == inside(b, ownedBy: a.id)
    }

    /// `definition`'s inside with its Group Input and Group Output naming `owner`.
    private static func inside(_ definition: GroupDefinition, ownedBy owner: GroupID) -> Graph {
        var graph = definition.graph
        for (nodeID, node) in graph.nodes where GroupNodes.isBoundary(node) {
            graph.nodes[nodeID]?.inputValues[NodeSetting.group] = .group(owner)
        }
        return graph
    }
}

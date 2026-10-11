import CreatorKernel

/// Where one level of an evaluation sits (groups spec §5): the top level, or the inside of a group node.
struct EvaluationScope: Sendable {
    /// What a level's Group Input hands on: the group node's gathered inputs, unchanged, and their cache key.
    struct Bound: Sendable {
        var values: [SocketName: Value]
        var key: CacheKey
    }

    /// What every level of one evaluation shares: the registry carrying the definitions, and the parameters.
    let setup: EvaluationSetup
    /// The group nodes from the top level down to this level, each by its ID in its own graph. Empty on the top level.
    var path: [NodeID] = []
    /// The definitions being evaluated around this level, so a definition that contains itself stops.
    var groups: [GroupID] = []
    /// What this level's Group Input produces; `nil` on the top level.
    var bound: Bound?
    /// How a pick stored at this level names faces, mapped to the identities they're made under here: a pick in a
    /// definition names faces as if that definition were the top level (`GroupScopes.identity`), so it holds for
    /// every instance; a name this level doesn't have is looked up in the levels around it. Empty on the top level,
    /// where picks already name faces by the identities they're made under.
    var names: [NodeID: NodeID] = [:]

    /// The identity a node of this level evaluates under: its own ID on the top level, else `NodeID.scoped`.
    func identity(of id: NodeID) -> NodeID {
        path.isEmpty ? id : NodeID.scoped(path + [id])
    }

    /// The scope inside group node `node` of definition `group`, whose graph is `graph`.
    func entering(_ node: NodeID, group: GroupID, graph: Graph, bound: Bound) -> EvaluationScope {
        let inside = path + [node], groups = groups + [group]
        var entered: [NodeID: NodeID] = [:]
        for relative in GroupScopes.paths(in: graph, definitions: setup.registry.groups, entered: groups) {
            entered[GroupScopes.identity(relative)] = NodeID.scoped(inside + relative)
        }
        // The copies a pattern node inside placed are named by that node and the tool's: rename those pairs too.
        let placers = GroupScopes.placerPaths(in: graph, definitions: setup.registry.groups, registry: setup.registry,
                                              entered: groups)
        let names = names.merging(GroupScopes.lifting(entered, placers: Set(placers.map(GroupScopes.identity)))) { _, new in new }
        return EvaluationScope(setup: setup, path: inside, groups: groups, bound: bound, names: names)
    }

    /// `node` with the picks it stores naming faces by the identities they're made under at this level.
    func naming(_ node: Node) -> Node {
        node.renamingTags(names)
    }
}

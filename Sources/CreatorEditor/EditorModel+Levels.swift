import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The level the graph panel shows (groups spec §6): the top level, or the inside of a group node entered from it,
/// and so on down. The level is view state, never undone and not saved: `enteredGroups` names the group nodes
/// entered, each by its ID in the graph before it. Everything else in the editor reads `graph`, which is the level's,
/// and edits through `edit(_:coalescingKey:)`, which addresses the level's graph path.
extension EditorModel {
    /// The group nodes entered from the top level, outermost first, that still exist. After Undo removes one, the
    /// panel shows the level around it (`refreshLevel()` makes that official).
    public var levelPath: [NodeID] {
        enteredGroups.isEmpty ? [] : document.content.existingLevels(enteredGroups)
    }

    /// Whether the panel shows the inside of a group.
    public var isInsideGroup: Bool { !levelPath.isEmpty }

    /// The graph the level shows, addressed by commands as `graphPath`.
    public var graphPath: GraphPath {
        enteredGroups.isEmpty ? .root : document.content.path(entering: levelPath) ?? .root
    }

    /// The top-level graph, whichever level is shown: the document's parameters live here.
    public var rootGraph: Graph { document.graph }

    /// Applies `command` to the graph the panel shows, as one undo step named `name` (`DocumentModel.perform(_:at:)`;
    /// without one the step is named from the command).
    public func edit(_ command: GraphCommand, coalescingKey: String? = nil, name: String? = nil) throws(GraphError) {
        try document.perform(command, at: graphPath, coalescingKey: coalescingKey, name: name)
    }

    /// The result of node `id` of the graph shown: from the top-level results, or from the results inside the group
    /// node entered (`DocumentModel.innerResults`), where the document evaluates the whole level
    /// (`DocumentModel.inspectedLevel`).
    public func result(of id: NodeID) -> NodeResult? {
        isInsideGroup ? document.innerResults[levelPath + [id]] : document.results[id]
    }

    /// The results of the graph shown, by node.
    public var levelResults: [NodeID: NodeResult] {
        let path = levelPath
        guard !path.isEmpty else { return document.results }
        var results: [NodeID: NodeResult] = [:]
        for (key, result) in document.innerResults where key.count == path.count + 1 && key.starts(with: path) {
            if let id = key.last { results[id] = result }
        }
        return results
    }

    /// "Graph", then each group entered by its definition's name.
    public var breadcrumbs: [Breadcrumb] {
        var crumbs = [Breadcrumb(title: "Graph", depth: 0)]
        let content = document.content
        var path = GraphPath.root
        for (index, id) in levelPath.enumerated() {
            guard let node = content.graph(at: path)?.nodes[id], let definition = registry.group(of: node) else { break }
            crumbs.append(Breadcrumb(title: definition.name, depth: index + 1))
            path = .definition(definition.id)
        }
        return crumbs
    }

    /// Enters group node `id` of the graph shown (a double click, ⌘↓, "Edit Group"). The selection clears, and the
    /// level shows with the pan and zoom it had last time, or framing everything the first time. Returns false for
    /// anything that isn't a group node whose definition exists, while a drag is under way, or while the level is
    /// locked (`isLevelLocked`).
    @discardableResult
    public func enterGroup(_ id: NodeID) -> Bool {
        let entered = levelPath + [id]
        guard interaction == nil, !isLevelLocked, document.content.path(entering: entered) != nil else { return false }
        changeLevel(to: entered)
        return true
    }

    /// ⌘↑: out of the group shown, one level. Returns false on the top level, so the key goes on.
    @discardableResult
    public func exitGroup() -> Bool {
        guard isInsideGroup, interaction == nil, !isLevelLocked else { return false }
        changeLevel(to: Array(levelPath.dropLast()))
        return true
    }

    /// A click on a breadcrumb: back out to `depth` (0 is the top level). Does nothing for the level shown, or a
    /// deeper one, or while the level is locked.
    public func goToLevel(_ depth: Int) {
        guard depth >= 0, depth < levelPath.count, interaction == nil, !isLevelLocked else { return }
        changeLevel(to: Array(levelPath.prefix(depth)))
    }

    /// Makes a level that no longer exists official: after Undo removes the group node entered, the panel falls back to
    /// the level around it, with nothing selected. Call it after anything that undoes or redoes.
    public func refreshLevel() {
        let existing = levelPath
        guard existing != enteredGroups else { return }
        changeLevel(to: existing)
    }

    /// Shows `levels`: commits a typed value for the node it was typed on, clears the selection, closes the palette,
    /// and gives the new level its own pan and zoom.
    private func changeLevel(to levels: [NodeID]) {
        commitPendingEntry()
        clearSelection()
        palette = nil
        lastNodeClick = nil
        enteredGroups = levels
        document.inspectedLevel = levels
        if !levels.isEmpty, levelTransforms[levels] == nil, let all = bounds(of: allItems) {
            transform = .framing(all, in: visibleCanvasSize, padding: Self.framingPadding)
        }
    }
}

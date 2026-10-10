import CreatorGraph
import CreatorKernel

extension EditorModel {
    /// ⌘G: groups the selected nodes of the level shown into a new definition and selects its group node, as one undo
    /// step (groups spec §5). A refused group changes nothing and shows its message.
    public func groupSelection() {
        run(UndoName.group, refusing: nil) { () throws(GraphError) in
            try GroupCommands.group(selection, in: graphPath, of: document.content, registry: registry)
        }
    }

    /// ⇧⌘G: ungroups the one selected group node and selects the nodes it spliced back, as one undo step.
    public func ungroupSelection() {
        guard selection.count == 1, let id = selection.first else {
            refuse("Select one group node to ungroup.", node: nil)
            return
        }
        ungroup(id)
    }

    /// Ungroups group node `id` of the level shown (its inspector's Ungroup, or ⇧⌘G).
    public func ungroup(_ id: NodeID) {
        run(UndoName.ungroup, refusing: id) { () throws(GraphError) in
            try GroupCommands.ungroup(id, in: graphPath, of: document.content, registry: registry)
        }
    }

    /// Make Unique on group node `id` of the level shown: it gets its own copy of the definition, as one undo step.
    public func makeUnique(_ id: NodeID) {
        run(UndoName.makeUnique, refusing: id) { () throws(GraphError) in
            try GroupCommands.makeUnique(id, in: graphPath, of: document.content, registry: registry)
        }
    }

    /// Performs the group command `build` makes as one undo step named `name` and selects what it says, or shows why it was
    /// refused (shaking `node`).
    private func run(_ name: String, refusing node: NodeID?, _ build: () throws(GraphError) -> GroupEdit) {
        do {
            let edit = try build()
            try document.perform(edit.command, name: name)
            clearRefusal()
            selection = edit.selection
        } catch {
            refuse(error.message, node: node)
        }
    }

    /// ⌘G, ⇧⌘G, ⌘↓ and ⌘↑. Returns false when the key does nothing here, so it can go on: ⌘G and ⇧⌘G with nothing
    /// selected, ⌘↓ without one group node selected, ⌘↑ on the top level, and all four while the panel is hidden.
    /// During a drag they are claimed and do nothing, so a move stays one undo step.
    func performGroupKey(_ command: GraphKeyCommand) -> Bool {
        switch command {
        case .group, .ungroup:
            guard !selection.isEmpty else { return false }
            if command == .ungroup { ungroupSelection() } else { groupSelection() }
            return true
        case .enterGroup, .exitGroup:
            guard isPanelVisible else { return false }
            guard interaction == nil else { return true }
            if command == .exitGroup { return exitGroup() }
            guard selection.count == 1, let id = selection.first else { return false }
            return enterGroup(id)
        default:
            return false
        }
    }
}

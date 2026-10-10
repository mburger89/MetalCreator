import CreatorGraph

extension EditorModel {
    /// ⌘G: groups the selected nodes into a new definition and selects its group node, as one undo step (groups
    /// spec §5). The panel shows only the top level until C2 adds entering groups, so it groups there. A refused
    /// group changes nothing and shows its message.
    public func groupSelection() {
        do {
            let edit = try GroupCommands.group(selection, in: .root, of: document.content, registry: registry)
            try document.perform(edit.command)
            selection = edit.selection
        } catch {
            refuse(error.message, node: nil)
        }
    }

    /// ⌘G and ⇧⌘G. Returns false with nothing selected, so the key can go on.
    func performGroupKey(_ command: GraphKeyCommand) -> Bool {
        guard !selection.isEmpty else { return false }
        if command == .ungroup { ungroupSelection() } else { groupSelection() }
        return true
    }

    /// ⇧⌘G: ungroups the one selected group node and selects the nodes it spliced back, as one undo step.
    public func ungroupSelection() {
        guard selection.count == 1, let id = selection.first else {
            refuse("Select one group node to ungroup.", node: nil)
            return
        }
        do {
            let edit = try GroupCommands.ungroup(id, in: .root, of: document.content, registry: registry)
            try document.perform(edit.command)
            selection = edit.selection
        } catch {
            refuse(error.message, node: id)
        }
    }
}

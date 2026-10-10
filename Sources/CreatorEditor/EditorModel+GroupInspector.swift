import CreatorGraph
import CreatorKernel

/// The inspector's group editing (groups spec §6): the definition's name and accent, its sockets (rename, reorder,
/// remove) and deleting an unused definition. Each is one `DocumentModel.perform`, so one undo step; a refusal shows
/// its message.
extension EditorModel {
    /// The panel for the one selected group node, Group Input or Group Output; `nil` for anything else.
    public var groupPanel: GroupPanel? {
        guard selection.count == 1, let id = selection.first, let node = graph.nodes[id],
              GroupNodes.typeIDs.contains(node.typeID), let definition = registry.group(of: node) else { return nil }
        let side: GroupSocketSide? = switch node.typeID {
        case GroupNodes.inputTypeID: .input
        case GroupNodes.outputTypeID: .output
        default: nil
        }
        let specs = side == .input ? definition.inputs : side == .output ? definition.outputs : []
        let sockets = specs.enumerated().map { index, spec in
            GroupPanel.SocketRow(name: spec.name, type: spec.type, canMoveUp: index > 0, canMoveDown: index < specs.count - 1)
        }
        return GroupPanel(node: id, definition: definition.id, name: definition.name, accent: definition.accent,
                          uses: GroupDependencies.instances(of: definition.id, in: document.content).count,
                          side: side, sockets: sockets)
    }

    /// Renames definition `id`, and the group nodes still named after it. A refusal shakes `node`, the node the name was
    /// typed for (`GroupPanel.node`), which is no longer the selected one when a click away commits the entry; with
    /// none, it only shows the message.
    public func renameGroup(_ id: GroupID, to name: String, on node: NodeID? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != document.definitions[id]?.name else { return }
        perform(UndoName.renameGroup, on: node) { () throws(GraphError) in
            try GroupCommands.rename(id, to: trimmed, in: document.content)
        }
    }

    public func setGroupAccent(_ id: GroupID, to accent: AccentRole, on node: NodeID? = nil) {
        guard accent != document.definitions[id]?.accent else { return }
        perform(UndoName.changeGroupAccent, on: node) { () throws(GraphError) in
            try GroupCommands.setAccent(id, accent, in: document.content)
        }
    }

    /// Renames socket `old` of `side` to `new`, on the definition, its wires inside and every group node of it. A
    /// refusal shakes `node` (see `renameGroup`).
    public func renameGroupSocket(_ id: GroupID, side: GroupSocketSide, from old: SocketName, to new: String,
                                  on node: NodeID? = nil) {
        let name = SocketName(new.trimmingCharacters(in: .whitespaces))
        guard name != old else { return }
        perform(UndoName.renameSocket, on: node) { () throws(GraphError) in
            try GroupCommands.renameSocket(id, side: side, from: old, to: name, in: document.content)
        }
    }

    /// Moves socket `name` of `side` one place up (`by` -1) or down (+1) the list; wires follow it by name. A move past
    /// either end does nothing.
    public func moveGroupSocket(_ id: GroupID, side: GroupSocketSide, named name: SocketName, by step: Int,
                                on node: NodeID? = nil) {
        let sockets = side == .input ? document.definitions[id]?.inputs : document.definitions[id]?.outputs
        guard let sockets, let index = sockets.firstIndex(where: { $0.name == name }),
              sockets.indices.contains(index + step) else { return }
        perform(UndoName.moveSocket, on: node) { () throws(GraphError) in
            try GroupCommands.moveSocket(id, side: side, from: index, to: index + step, in: document.content)
        }
    }

    /// Removes socket `name` of `side` and its wires inside. Refused while a group node has it wired, naming that node.
    public func removeGroupSocket(_ id: GroupID, side: GroupSocketSide, named name: SocketName, on node: NodeID? = nil) {
        perform(UndoName.removeSocket, on: node) { () throws(GraphError) in
            try GroupCommands.removeSocket(id, side: side, name: name, in: document.content)
        }
    }

    /// Deletes definition `id` from the document. Refused while a group node uses it.
    public func deleteGroup(_ id: GroupID) {
        perform(UndoName.deleteGroup, on: nil) { () throws(GraphError) in
            try GroupCommands.deleteDefinition(id, in: document.content)
        }
    }

    private func perform(_ name: String, on node: NodeID?, _ build: () throws(GraphError) -> GraphCommand) {
        do {
            try document.perform(try build(), name: name)
            clearRefusal()
        } catch {
            refuse(error.message, node: node)
        }
    }
}

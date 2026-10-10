import CreatorGraph
import CreatorKernel

/// The "+" socket of Group Input and Group Output (groups spec §6): dropping a wire on it exposes a new socket.
extension EditorModel {
    static let exposeHint = "Drop a wire from an output on Group Output's +, or drag from Group Input's + onto an input."

    /// Whether `socket` is the "+" of Group Input or Group Output.
    func isPlus(_ socket: SocketRef) -> Bool {
        socket.endpoint.socket == GroupNaming.plusSocket
    }

    /// A wire dragged between two sockets, one of them a "+" (either end can be the one dragged from). An output
    /// dropped on Group Output's "+" exposes a new output, wired from it; Group Input's "+" dragged onto an input
    /// exposes a new input, wired to it. Each is one undo step (`GroupCommands.exposeOutput`, `exposeInput`); anything
    /// else is refused with a hint.
    func exposeSocket(_ first: SocketRef, _ second: SocketRef) {
        let (plus, other) = isPlus(first) ? (first, second) : (second, first)
        guard !isPlus(other), let boundary = graph.nodes[plus.endpoint.node],
              let definition = boundary.inputValues[NodeSetting.group]?.groupID else {
            refuse(Self.exposeHint, node: plus.endpoint.node)
            return
        }
        do {
            switch (boundary.typeID, plus.isInput, other.isInput) {
            case (GroupNodes.outputTypeID, true, false):
                try document.perform(GroupCommands.exposeOutput(from: other.endpoint, on: boundary.id, in: definition,
                                                                of: document.content, registry: registry),
                                     name: UndoName.addOutputSocket)
                clearRefusal()
            case (GroupNodes.inputTypeID, false, true):
                try document.perform(GroupCommands.exposeInput(to: other.endpoint, from: boundary.id, in: definition,
                                                               of: document.content, registry: registry),
                                     name: UndoName.addInputSocket)
                clearRefusal()
            default:
                refuse(Self.exposeHint, node: plus.endpoint.node)
            }
        } catch {
            refuse(error.message, node: plus.endpoint.node)
        }
    }
}

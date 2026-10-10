import CreatorKernel

/// What a group command builds (groups spec §5): the command to perform, one undo step, and the nodes to select after
/// it. The command also renames the picks the edit would otherwise strand (`GroupScopes.renamingPicks`), so every pick
/// keeps naming the faces it named.
public struct GroupEdit: Sendable, Equatable {
    public var command: GraphCommand
    public var selection: Set<NodeID>

    public init(command: GraphCommand, selection: Set<NodeID>) {
        self.command = command
        self.selection = selection
    }
}

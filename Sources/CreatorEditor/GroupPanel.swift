import CreatorGraph
import CreatorKernel

/// What the inspector shows about the group definition behind the selected node (groups spec §6): its name, accent
/// and how many group nodes use it; and, when the selection is Group Input or Group Output, the sockets of that side.
public struct GroupPanel: Equatable, Sendable {
    /// One socket of the side shown, with whether it can move up or down the list.
    public struct SocketRow: Equatable, Sendable, Identifiable {
        public var name: SocketName
        public var type: SocketType
        public var canMoveUp: Bool
        public var canMoveDown: Bool

        public var id: String { name.rawValue }
    }

    /// The node the panel is for (the group node, Group Input or Group Output): an edit the panel makes that is
    /// refused shakes this node, whatever is selected by the time a typed name is committed.
    public var node: NodeID
    public var definition: GroupID
    public var name: String
    public var accent: AccentRole
    /// Group nodes of the definition, on every level.
    public var uses: Int
    /// Group Input's side (`.input`) or Group Output's (`.output`) when one of them is selected, else `nil`.
    public var side: GroupSocketSide?
    public var sockets: [SocketRow]

    /// "Used 1 time", "Used 3 times".
    public var usesText: String { "Used \(uses) \(uses == 1 ? "time" : "times")" }
}

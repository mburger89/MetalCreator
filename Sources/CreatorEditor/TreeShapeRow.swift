import CreatorGraph
import CreatorKernel

/// A data tree on one socket of the selected node, as the inspector's Data section shows it (7a spec §2): its shape
/// ("3 × 8", or the branch counts when they differ) and, when opened, each branch's path with its item count.
public struct TreeShapeRow: Equatable, Sendable {
    /// One branch: its path (`{0;3}`) and how many items it holds.
    public struct Entry: Equatable, Sendable {
        public var path: String
        public var count: Int
    }

    /// The most branches listed; `hiddenCount` says how many more there are.
    public static let maximumEntries = 50

    /// Names the list for opening and closing it: the node and the socket (`EditorModel.toggleShapeList(_:)`).
    public var key: String
    public var label: String
    public var summary: String
    public var entries: [Entry]
    public var hiddenCount: Int
    public var isExpanded: Bool

    public init(key: String, label: String, tree: DataTree, isExpanded: Bool) {
        let leaves = tree.leaves
        self.key = key
        self.label = label
        self.summary = tree.shapeText
        self.entries = leaves.prefix(Self.maximumEntries).map { Entry(path: $0.path.description, count: $0.items.count) }
        self.hiddenCount = max(leaves.count - Self.maximumEntries, 0)
        self.isExpanded = isExpanded
    }

    /// The key of a socket's list: "<node>/in.tree" or "<node>/out.tree".
    public static func key(node: NodeID, isInput: Bool, socket: SocketName) -> String {
        "\(node.rawValue.uuidString)/\(isInput ? "in." : "out.")\(socket.rawValue)"
    }
}

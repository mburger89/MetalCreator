/// What a socket carries: a single item, a list that broadcasts, or a data tree (spec §4.2, and sub-project 7a §2).
/// A flat list is a tree of depth 1, so every node that only knows lists works unchanged. Don't assume exactly three
/// cases.
public enum Value: Sendable {
    case one(Scalar)
    case list([Scalar])
    /// Nested lists of depth 2 or more; `Value(_:)` turns a flat `DataTree` into a `.list`.
    case tree(DataTree)

    /// The value of `tree`: a flat list for depth 1, else `.tree`.
    public init(_ tree: DataTree) {
        self = tree.depth == 1 ? .list(tree.items) : .tree(tree)
    }

    /// How many indices an item's path has: 0 for one item, 1 for a list, the tree's depth otherwise.
    public var depth: Int {
        switch self {
        case .one: 0
        case .list: 1
        case .tree(let tree): tree.depth
        }
    }

    /// Every item, branch by branch.
    public var items: [Scalar] {
        switch self {
        case .one(let scalar): [scalar]
        case .list(let scalars): scalars
        case .tree(let tree): tree.items
        }
    }

    /// The value as a tree: a list is a tree of depth 1; one item has no tree form (`nil`).
    public var asTree: DataTree? {
        switch self {
        case .one: nil
        case .list(let scalars): .list(scalars)
        case .tree(let tree): tree
        }
    }

    public func converted(to target: SocketType) -> Value? {
        switch self {
        case .one(let scalar):
            return scalar.converted(to: target).map(Value.one)
        case .list(let scalars):
            let converted = scalars.compactMap { $0.converted(to: target) }
            return converted.count == scalars.count ? .list(converted) : nil
        case .tree(let tree):
            return tree.mapItems { $0.converted(to: target) }.map(Value.tree)
        }
    }

    public var estimatedBytes: Int {
        switch self {
        case .tree(let tree): tree.estimatedBytes
        case .one, .list: items.reduce(16) { $0 + $1.estimatedBytes }
        }
    }
}

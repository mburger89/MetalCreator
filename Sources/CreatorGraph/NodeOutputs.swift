/// What one broadcast iteration of a node produced.
public struct NodeOutputs: Sendable {
    /// One item per output socket for this iteration.
    public var values: [SocketName: Scalar]
    /// Whole lists for generator nodes (Series, Grid Points, …). A socket listed here always
    /// becomes a `.list` output, and its items are appended for each iteration.
    public var lists: [SocketName: [Scalar]]
    /// Whole trees for the tree nodes (Flatten, Graft, Partition, …): a socket listed here becomes that tree as it is.
    /// Only a node that runs once may return one, so its other inputs must be single values.
    public var trees: [SocketName: DataTree] = [:]
    /// Non-fatal problems, such as a selection rule matching a different number of edges.
    public var warnings: [String]

    public init(_ values: [SocketName: Scalar] = [:], warnings: [String] = []) {
        self.values = values
        self.lists = [:]
        self.warnings = warnings
    }

    public init(lists: [SocketName: [Scalar]], warnings: [String] = []) {
        self.values = [:]
        self.lists = lists
        self.warnings = warnings
    }

    /// A node's output sockets as whole trees, plus single items for the others.
    public init(trees: [SocketName: DataTree], values: [SocketName: Scalar] = [:], warnings: [String] = []) {
        self.values = values
        self.lists = [:]
        self.trees = trees
        self.warnings = warnings
    }
}

// Test fixture file: sources of trees and readers of culled ones, shared by the variation nodes' tests.
import CreatorGraph
import CreatorNodes
import Testing

/// A node and the output socket that carries a list or tree.
struct TreeSource {
    let node: Node
    let socket: SocketName
}

extension Harness {
    /// A Series 0, 1, 2 … of `count` numbers, partitioned into rows of `rows` when that is given: a flat list or a tree.
    mutating func source(count: Int, rows: Int? = nil) -> TreeSource {
        let series = add(SeriesNode.self, ["count": .integer(count)])
        guard let rows else { return TreeSource(node: series, socket: "values") }
        let partition = add(PartitionNode.self, ["size": .integer(rows)])
        wire(series, "values", to: partition, "tree")
        return TreeSource(node: partition, socket: "tree")
    }

    mutating func wire(_ source: TreeSource, to node: Node, _ input: SocketName) {
        wire(source.node, source.socket, to: node, input)
    }
}

extension EvaluationReport {
    /// The tree (or list) on an output, with its culling.
    func tree(_ node: Node, _ socket: SocketName = "tree") -> DataTree? { value(node, socket)?.asTree }

    /// Each branch's item indices, in branch order: `[[0, 2], [0, 3]]`.
    func positions(_ node: Node, _ socket: SocketName = "tree") -> [[Int]]? { tree(node, socket)?.leaves.map(\.positions) }
}

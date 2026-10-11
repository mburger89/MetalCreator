// Test fixture file: a few small node definitions for the tree tests. They live in `treeRegistry`, not in
// `testRegistry`, because a test counts that registry's nodes.
import CreatorKernel
@testable import CreatorGraph

/// `rows` branches of `columns` numbers each, numbered 0, 1, 2, … in order: a tree made from nothing.
enum TreeSourceNode: NodeDefinition {
    static let typeID = "test.treeSource"
    static let displayName = "Tree Source"
    static let category = NodeCategory.lists
    static let inputs = [
        SocketSpec("rows", .integer, defaultValue: .integer(2)),
        SocketSpec("columns", .integer, defaultValue: .integer(3)),
    ]
    static let outputs = [SocketSpec("values", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (rows, columns) = (try inputs.integer("rows"), try inputs.integer("columns"))
        let branches = (0..<rows).map { row in
            DataTree.list((0..<columns).map { .number(Double(row * columns + $0)) })
        }
        return NodeOutputs(trees: ["values": DataTree(depth: 2, branches: branches) ?? .empty(depth: 2)])
    }
}

/// Reports the depth and the item count of the whole tree it is given.
enum TreeDepthNode: NodeDefinition {
    static let typeID = "test.treeDepth"
    static let displayName = "Tree Depth"
    static let category = NodeCategory.lists
    static let inputs = [SocketSpec("tree", .any, access: .tree)]
    static let outputs = [SocketSpec("depth", .integer), SocketSpec("count", .integer)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("tree")
        return NodeOutputs(["depth": .integer(tree.depth), "count": .integer(tree.itemCount)])
    }
}

/// Grafts the tree it is given `times` times: a tree node that also has an item input.
enum TreeGraftNode: NodeDefinition {
    static let typeID = "test.treeGraft"
    static let displayName = "Tree Graft"
    static let category = NodeCategory.lists
    static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("times", .integer, defaultValue: .integer(1)),
    ]
    static let outputs = [SocketSpec("tree", .any)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        var tree = try inputs.tree("tree")
        for _ in 0..<(try inputs.integer("times")) { tree = tree.grafted() }
        return NodeOutputs(trees: ["tree": tree])
    }
}

/// The whole numbers 0, 1, …, count − 1 as one list.
enum IntListNode: NodeDefinition {
    static let typeID = "test.intList"
    static let displayName = "Int List"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("count", .integer, defaultValue: .integer(2))]
    static let outputs = [SocketSpec("values", .integer)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["values": (0..<(try inputs.integer("count"))).map { .integer($0) }])
    }
}

let treeRegistry = NodeRegistry([
    ConstantNode.self, AddNode.self, SumListNode.self, ListSourceNode.self, IntListNode.self,
    TreeSourceNode.self, TreeDepthNode.self, TreeGraftNode.self,
])

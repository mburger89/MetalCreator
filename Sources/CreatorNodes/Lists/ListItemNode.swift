import CreatorGraph
import Foundation
import CreatorKernel

/// Takes the item at `index` from every branch (7a spec §4), counting from 0. The result keeps the branches, one item
/// each, so it still lines up with the tree it came from; a branch too short to have that item contributes nothing and
/// the node says how many did.
/// A path in the `itemPath` setting (`{0;3}`: branch 0, item 3) takes that one item instead and the index is ignored.
public enum ListItemNode: NodeDefinition {
    public static let typeID = "creator.listItem"
    public static let displayName = "List Item"
    public static let category = NodeCategory.lists
    public static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("index", .integer, defaultValue: .integer(0), unit: .count),
    ]
    public static let outputs = [SocketSpec("item", .any)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.itemPath: .text("")]
    public static let inspector = [
        InspectorSection(title: "List item", controls: [.integer("index"), .text(NodeSetting.itemPath)]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("tree")
        if let path = try itemPath(of: context.node) { return try item(at: path, in: tree) }
        let index = try inputs.integer("index")
        guard index >= 0 else { throw NodeError.invalidValue("“index” can't be negative. The first item is 0.") }
        let picked = tree.picking(itemAt: index)
        guard picked.missing > 0 else { return NodeOutputs(trees: ["item": picked.tree]) }
        let branches = tree.leaves.count
        let warning = "\(picked.missing.display) of \(branches.display) \(branches == 1 ? "branch has" : "branches have") "
            + "no item \(index.display)."
        return NodeOutputs(trees: ["item": picked.tree], warnings: [warning])
    }

    /// The path in the `itemPath` setting; `nil` when it is empty (then the index is used).
    private static func itemPath(of node: Node) throws -> TreePath? {
        guard case .text(let text)? = node.inputValues[NodeSetting.itemPath] else { return nil }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let path = TreePath(parsing: text) else {
            throw NodeError.invalidValue("“\(text)” isn't a path. Write it like {0;3}.")
        }
        return path
    }

    /// The one item a full path names: one index per level of branches, then the item's index. Never a neighbour.
    private static func item(at path: TreePath, in tree: DataTree) throws -> NodeOutputs {
        guard path.count == tree.depth else {
            let example = TreePath(Array(repeating: 0, count: tree.depth))
            throw NodeError.invalidValue("\(path) has \(path.count.display) \(path.count == 1 ? "index" : "indices"), but an item of "
                + "this tree (\(tree.shapeText)) needs \(tree.depth.display). Write it like \(example).")
        }
        var current = tree
        for (level, index) in path.indices.dropLast().enumerated() {
            guard index < current.count else {
                let here = TreePath(Array(path.indices.prefix(level + 1)))
                let owner = level == 0 ? "the tree has" : "\(TreePath(Array(path.indices.prefix(level)))) has"
                throw NodeError.invalidValue("No branch \(here): \(owner) \(current.count.display) "
                    + "\(current.count == 1 ? "branch" : "branches").")
            }
            current = current.branches[index]
        }
        let last = path.indices[path.count - 1]
        guard current.items.indices.contains(last) else {
            let owner = TreePath(Array(path.indices.dropLast()))
            throw NodeError.invalidValue("No item \(path): \(owner) has \(current.count.display) \(current.count == 1 ? "item" : "items").")
        }
        return NodeOutputs(trees: ["item": .list([current.items[last]])])
    }
}

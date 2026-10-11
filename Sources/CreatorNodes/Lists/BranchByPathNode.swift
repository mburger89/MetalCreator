import CreatorGraph
import CreatorKernel

/// Takes the branch at a path such as `{0;3}` (7a spec §4). A path names a branch with one index per level of
/// branches, so a 3 × 8 tree has the branches `{0}`, `{1}` and `{2}`, and a flat list has the one branch `{}`. A path
/// with fewer indices takes everything under it. The path is a saved text setting.
public enum BranchByPathNode: NodeDefinition {
    public static let typeID = "creator.branchByPath"
    public static let displayName = "Branch by Path"
    public static let category = NodeCategory.lists
    public static let inputs = [SocketSpec("tree", .any, access: .tree)]
    public static let outputs = [SocketSpec("branch", .any)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.branchPath: .text("{0}")]
    public static let inspector = [InspectorSection(title: "Branch", controls: [.text(NodeSetting.branchPath)])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("tree")
        guard case .text(let text)? = context.node.inputValues[NodeSetting.branchPath], let path = TreePath(parsing: text) else {
            let shown = context.node.inputValues[NodeSetting.branchPath].flatMap { value -> String? in
                if case .text(let text) = value { text } else { nil }
            } ?? ""
            throw NodeError.invalidValue("“\(shown)” isn't a path. Write it like {0} or {1;3}.")
        }
        let levels = tree.depth - 1
        guard path.count <= levels else {
            let example = TreePath(Array(repeating: 0, count: levels))
            throw NodeError.invalidValue("\(path) names a branch with \(path.count.display) indices, but this tree's branches "
                + "(\(tree.shapeText)) have \(levels.display). Write it like \(example).")
        }
        var current = tree
        for (level, index) in path.indices.enumerated() {
            guard index < current.count else {
                let here = TreePath(Array(path.indices.prefix(level + 1)))
                let owner = level == 0 ? "the tree has" : "\(TreePath(Array(path.indices.prefix(level)))) has"
                let count = current.count
                throw NodeError.invalidValue("No branch \(here): \(owner) \(count.display) \(count == 1 ? "branch" : "branches").")
            }
            current = current.branches[index]
        }
        return NodeOutputs(trees: ["branch": current])
    }
}

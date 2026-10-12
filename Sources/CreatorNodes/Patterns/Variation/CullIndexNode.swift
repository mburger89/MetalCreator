import CreatorGraph
import CreatorKernel
import Foundation

/// Takes listed items out of a list or tree (patterns spec §4). An index such as `3` drops that place from every branch (the
/// place within the branch: in a tree whose branches hold one item each, like a Face Pattern's `{row;column;0}` cells, only 0
/// is a place, so name cells by path); a path such as `{0;3}` drops one item, and a shorter one such as `{1}` drops everything
/// under it. They go in the saved text
/// setting, `1, 4, {0;3}`, or as numbers wired into `indices` (a Series, Random Values' integers). Culling keeps paths: the
/// rest keep the indices they had, so `{4}` is still `{4}` when `{1}` is gone and a pick on it follows it (§6); a pick on the
/// culled item warns, naming its path. A path that names nothing in the tree is said once and the others still apply.
public enum CullIndexNode: NodeDefinition {
    public static let typeID = "creator.cullIndex"
    public static let displayName = "Cull Index"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("indices", .number, access: .list, optional: true),
    ]
    public static let outputs = [SocketSpec("tree", .any)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.cullIndices: .text("")]
    public static let inspector = [InspectorSection(title: "Cull", controls: [.text(NodeSetting.cullIndices)])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("tree")
        var targets = try CullTargets(parsing: setting(of: context.node))
        if inputs.has("indices") { try targets.add(wired: try inputs.numbers("indices")) }
        try targets.validate(against: tree)
        let depth = tree.depth
        let culled = tree.keepingItems { leaf, _, k in !targets.drops(leaf, at: k, depth: depth) }
        return NodeOutputs(trees: ["tree": culled], warnings: warning(for: targets.unmatched(in: tree)).map { [$0] } ?? [])
    }

    /// The text setting; none stored is the same as empty.
    private static func setting(of node: Node) -> String {
        if case .text(let text)? = node.inputValues[NodeSetting.cullIndices] { text } else { "" }
    }

    /// "{0;9} names nothing in this tree." for the paths nothing is at, or `nil`.
    private static func warning(for unmatched: [TreePath]) -> String? {
        guard !unmatched.isEmpty else { return nil }
        let names = unmatched.map(\.description).formatted(.list(type: .and).locale(.messages))
        return "\(names) \(unmatched.count == 1 ? "names" : "name") nothing in this tree."
    }
}

import CreatorGraph
import CreatorKernel

/// Reshapes a tree by a text rule, `source → target` (7a spec §4; `PathRule` has the syntax): `{A;B} → {B;A}` swaps rows
/// and columns, `{A;B} → {A}` merges each row, `{A;B} → {A;B%2}` folds the columns in two, `{A} → {(i)}` sends each item
/// to the branch of its own index. A rule that doesn't read, or whose source has a different number of levels than the
/// tree, refuses naming the part that failed; a rule that matches only some branches warns and leaves the rest where
/// they were. The rule is a saved text setting.
public enum PathMapperNode: NodeDefinition {
    public static let typeID = "creator.pathMapper"
    public static let displayName = "Path Mapper"
    public static let category = NodeCategory.lists
    public static let inputs = [SocketSpec("tree", .any, access: .tree)]
    public static let outputs = [SocketSpec("tree", .any)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.pathRule: .text("{A} → {A}")]
    public static let inspector = [InspectorSection(title: "Rule", controls: [.text(NodeSetting.pathRule)])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let text: String
        if case .text(let stored)? = context.node.inputValues[NodeSetting.pathRule] { text = stored } else { text = "" }
        do {
            let result = try PathRuleParser.parse(text).apply(to: try inputs.tree("tree"))
            guard result.matched < result.total else { return NodeOutputs(trees: ["tree": result.tree]) }
            let others = result.total - result.matched
            var warning = "The rule matched \(result.matched.display) of \(result.total.display) branches; "
                + "the other \(others.display) stay where they were."
            if result.merged > 0 {
                warning += " \(result.merged.display) of them \(result.merged == 1 ? "shares a branch" : "share branches") "
                    + "with the results, so their items are mixed in."
            }
            return NodeOutputs(trees: ["tree": result.tree], warnings: [warning])
        } catch let error as PathRuleError {
            throw NodeError.invalidValue(error.message)
        }
    }
}

import CreatorGraph
import CreatorKernel

/// Keeps or culls the items of every branch by a repeating mask (patterns spec §4): `1 0` keeps every other item, `1 1 0`
/// culls every third. Per branch (the default) the mask starts again at the first item of each branch; Overall it runs on
/// along the whole tree, branch after branch, which is how one mask reaches every other cell of a `{row;column;0}` tree whose
/// branches hold one item each (User decision U16). Either way it counts the items there are now, so a second Cull Pattern
/// after a first works on what is left. Culling keeps paths: a survivor keeps the index it had, so
/// `{3}` is still `{3}` when `{1}` is gone and a pick on it follows it (§6). The mask is a saved text setting, or a list of
/// true and false wired into `keep`, which takes its place.
public enum CullPatternNode: NodeDefinition {
    public static let typeID = "creator.cullPattern"
    public static let displayName = "Cull Pattern"
    public static let category = NodeCategory.patterns
    public static let scopes = ["Per branch", "Overall"]
    public static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("keep", .bool, access: .list, optional: true),
        SocketSpec("scope", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("tree", .any)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.cullPattern: .text("1 0")]
    public static let inspector = [
        InspectorSection(title: "Pattern", controls: [.text(NodeSetting.cullPattern), .segmented("scope", options: scopes)]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("tree")
        let mask: [Bool]
        if inputs.has("keep") {
            mask = try inputs.bools("keep")
            guard !mask.isEmpty else { throw NodeError.invalidValue("“keep” is an empty list. Give it at least one true or false.") }
        } else {
            // A missing or non-text setting reads as empty; `CullMask.parse` says so.
            var text = ""
            if case .text(let setting)? = context.node.inputValues[NodeSetting.cullPattern] { text = setting }
            mask = try CullMask.parse(text)
        }
        // Where each branch's first item falls in the mask: the start for every branch, or after the items before it.
        var starts = Array(repeating: 0, count: tree.leaves.count)
        if try inputs.choice("scope", options: scopes) == 1 {
            var before = 0
            for (ordinal, leaf) in tree.leaves.enumerated() {
                starts[ordinal] = before
                before += leaf.items.count
            }
        }
        return NodeOutputs(trees: ["tree": tree.keepingItems { _, ordinal, k in mask[(starts[ordinal] + k) % mask.count] }])
    }
}

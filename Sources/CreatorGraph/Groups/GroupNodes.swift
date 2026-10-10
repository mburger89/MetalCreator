/// The three node types groups are made of (groups spec §4). `NodeRegistry` registers them itself, so every registry
/// makes group nodes through `makeNode` and the evaluator, which runs them itself, finds them; the add-node palette and
/// the library don't list them (`NodeRegistry.all`).
public enum GroupNodes {
    /// A group node: one instance of the definition its `NodeSetting.group` names.
    public static let groupTypeID = "group"
    /// Inside a definition: stands for the group node's inputs (its outputs are the definition's inputs).
    public static let inputTypeID = "groupInput"
    /// Inside a definition: stands for the group node's outputs (its inputs are the definition's outputs).
    public static let outputTypeID = "groupOutput"

    public static let typeIDs: Set<String> = [groupTypeID, inputTypeID, outputTypeID]

    static let definitions: [any NodeDefinition.Type] = [GroupNode.self, GroupInputNode.self, GroupOutputNode.self]

    /// True for Group Input and Group Output, which exist only inside a definition, exactly once each.
    public static func isBoundary(_ node: Node) -> Bool {
        node.typeID == inputTypeID || node.typeID == outputTypeID
    }
}

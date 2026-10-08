/// What the viewport shows (spec §6.1): every Output node's solids, or only the selected node's output, for
/// stepping through the recipe.
public enum PreviewMode: String, CaseIterable, Sendable {
    case final
    case selectedNode

    public var title: String {
        switch self {
        case .final: "Final"
        case .selectedNode: "Selected node"
        }
    }
}

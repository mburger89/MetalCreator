/// The tools of DR-1 (the toolbar's others come with DR-2 to DR-5).
public enum DrawingTool: Hashable, Sendable, CaseIterable {
    case select
    case baseView
    case projectedView
}

extension DrawingTool {
    /// The tool's name on its button, or `nil` for Select, which has none (Esc returns to it).
    public var title: String? {
        switch self {
        case .select: nil
        case .baseView: "Base View"
        case .projectedView: "Projected View"
        }
    }
}

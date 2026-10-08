/// The viewport's shading menu (spec §6.3).
public enum ShadingMode: Hashable, Sendable, CaseIterable {
    case shaded
    case shadedEdges

    public var title: String {
        switch self {
        case .shaded: "Shaded"
        case .shadedEdges: "Shaded + Edges"
        }
    }
}

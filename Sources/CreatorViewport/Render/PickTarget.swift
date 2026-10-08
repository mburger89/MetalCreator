import CreatorKernel

/// What a pick found: a face or an edge of the solid at `solid` (its index in `ViewportModel.items`).
public enum PickTarget: Hashable, Sendable {
    case face(solid: Int, FaceID)
    case edge(solid: Int, EdgeID)

    public var solidIndex: Int {
        switch self {
        case .face(let solid, _), .edge(let solid, _): solid
        }
    }
}

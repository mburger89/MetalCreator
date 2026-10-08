import CreatorKernel

/// An item in the right-click menu on a model face (spec §6.3).
public enum ViewportMenuItem: Hashable, Sendable {
    case lookAt(ViewportFaceRef)
    case selectEdgesOfFace(ViewportFaceRef)
    /// One item per producing node. The title names the node when a face has several.
    case showProducingNode(NodeID, title: String)

    public var title: String {
        switch self {
        case .lookAt: "Look At"
        case .selectEdgesOfFace: "Select Edges of Face"
        case .showProducingNode(_, let title): title
        }
    }
}

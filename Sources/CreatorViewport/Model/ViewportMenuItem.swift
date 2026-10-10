import CreatorKernel

/// An item in the right-click menu on a model face (spec §6.3).
public enum ViewportMenuItem: Hashable, Sendable {
    case lookAt(ViewportFaceRef)
    case selectEdgesOfFace(ViewportFaceRef)
    /// A Plane from Face and a Sketch on it, opened for drawing (sketcher spec §8). Only on a flat face, only outside
    /// sketch mode.
    case newSketchOnFace(ViewportFaceRef)
    /// One item per producing node. The title names the node when a face has several.
    case showProducingNode(NodeID, title: String)

    public var title: String {
        switch self {
        case .lookAt: "Look At"
        case .selectEdgesOfFace: "Select Edges of Face"
        case .newSketchOnFace: "New Sketch on Face"
        case .showProducingNode(_, let title): title
        }
    }
}

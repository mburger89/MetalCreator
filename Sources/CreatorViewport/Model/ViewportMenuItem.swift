import CreatorKernel

/// An item in the right-click menu on a model face (spec §6.3).
public enum ViewportMenuItem: Hashable, Sendable {
    case lookAt(ViewportFaceRef)
    case selectEdgesOfFace(ViewportFaceRef)
    /// A Plane from Face and a Sketch on it, opened for drawing (sketcher spec §8). Only on a flat face, only outside
    /// sketch mode.
    case newSketchOnFace(ViewportFaceRef)
    /// A Face Pattern on the face, wired from the solid (patterns spec §3). Only on a flat face with a normal, like New Sketch.
    case patternOnFace(ViewportFaceRef)
    /// A Field Scatter on the face, wired from the solid (fields spec §3.3). Offered with the same faces as Pattern on Face.
    case scatterOnFace(ViewportFaceRef)
    /// A dimension on the model, started with this face or edge as its first pick (dimensions spec §3.5). Only outside sketch mode.
    case dimension(PickTarget)
    /// One item per producing node. The title names the node when a face has several.
    case showProducingNode(NodeID, title: String)
    /// An entry the host offers: a dimension's (over its text) or the tool's (`dimension` is `nil`).
    case host(HostMenuAction, dimension: OverlayDimensionID?)

    public var title: String {
        switch self {
        case .lookAt: "Look At"
        case .selectEdgesOfFace: "Select Edges of Face"
        case .dimension: "Dimension"
        case .newSketchOnFace: "New Sketch on Face"
        case .patternOnFace: "Pattern on Face"
        case .scatterOnFace: "Scatter on Face"
        case .showProducingNode(_, let title): title
        case .host(let action, _): action.title
        }
    }
}

import CreatorGraph
import CreatorKernel
import CreatorViewport

/// A dimension a feature node declared, with what editing it means and how the viewport draws it (spec §3.1).
struct FeatureDimension: Equatable {
    enum Editing: Equatable {
        /// A typed constant, or a sketch's driving, unwired dimension.
        case driving
        /// Wired from a Graph Parameter node: the edit changes the parameter, which `uses` features read.
        case parameter(ParameterID, name: String, uses: Int)
        /// Not editable here. `source` is "from Number “width”" for a wired value, `nil` for a sketch reference or a constant.
        case reference(source: String?)
    }

    var id: OverlayDimensionID
    var node: NodeID
    var spec: DimensionSpec
    var editing: Editing
    var isPinned: Bool
    /// What the viewport draws: the reading's text, tinted driving or reference.
    var overlay: OverlayDimension

    /// "feature/<node uuid>/<target.key>[.<component>]/<index among specs of that key>". The one place the ID is built;
    /// the builder and DIM-4 call it.
    static func overlayID(node: NodeID, target: DimensionTarget, component: Int? = nil, index: Int = 0) -> OverlayDimensionID {
        let key = component.map { "\(target.key).\($0)" } ?? target.key
        return OverlayDimensionID("feature/\(node.rawValue.uuidString)/\(key)/\(index)")
    }
}

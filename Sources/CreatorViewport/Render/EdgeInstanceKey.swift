import CreatorKernel

/// What a mesh's edge instances depend on: the solid index (inside the pick IDs), the selection, the mode, the
/// pixel scale and whether the selection is drawn faded (a guide's edges behind the part).
struct EdgeInstanceKey: Hashable {
    var solid: Int
    var selected: Set<EdgeID>
    var selectedOnly: Bool
    var scale: Float
    var hidden = false
}

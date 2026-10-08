import CreatorKernel

/// What a mesh's edge instances depend on: the solid index (inside the pick IDs), the selection, the mode and
/// the pixel scale.
struct EdgeInstanceKey: Hashable {
    var solid: Int
    var selected: Set<EdgeID>
    var selectedOnly: Bool
    var scale: Float
}

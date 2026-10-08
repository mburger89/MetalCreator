import CreatorGeometry

/// What the ID buffer depends on. A pick re-renders it only when this changes. The ID pass is independent of hover,
/// selection, shading and ghost state, so none of those belong here.
struct PickKey: Hashable {
    var pose: CameraPose
    var size: ViewportSize
    /// (mesh serial, solid index) for each drawn item, flattened.
    var items: [Int]
}

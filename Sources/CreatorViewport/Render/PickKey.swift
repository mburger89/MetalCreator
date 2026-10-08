import CreatorGeometry

/// What the ID buffer depends on. A pick re-renders it only when this changes.
struct PickKey: Hashable {
    var pose: CameraPose
    var size: ViewportSize
    /// (mesh serial, solid index) for each drawn item, flattened.
    var items: [Int]
}

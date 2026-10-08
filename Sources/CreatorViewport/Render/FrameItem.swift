import CreatorKernel

/// One solid as the renderer sees it this frame.
struct FrameItem {
    /// The tessellation cache's serial for `mesh`. The GPU caches by it.
    var meshSerial: Int
    var mesh: DisplayMesh
    var solidIndex: Int
    var isGhost: Bool
    var hoveredFace: FaceID?
    var selectedFaces: Set<FaceID>
    var selectedEdges: Set<EdgeID>
}

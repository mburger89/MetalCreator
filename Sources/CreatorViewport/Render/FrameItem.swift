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
    /// Only the selected edges are drawn, over everything else (`ViewportItem.isGuide`).
    var isGuide = false
    /// The field tint (`ViewportItem.fieldValues`, `fieldRamp`).
    var fieldValues: [Float]?
    var fieldRamp: FieldRamp?
    /// The faces drawn in the warning colour (`ViewportItem.warningFaces`).
    var warningFaces: Set<FaceID> = []
    /// The faces of the solid that lie on an open shell (a sheet): their backs draw in the sheet-back colour.
    var openShellFaces: Set<FaceID> = []
    /// A curve (`ViewportItem.isCurve`): only its edges are drawn, in the reference colour, in every display mode.
    var isCurve = false
}

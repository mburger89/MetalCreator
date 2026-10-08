import CreatorKernel

/// One solid the viewport shows (spec §6.3). The host builds these from the document:
/// - output solids, and last-good results drawn as ghosts while their node is in error (spec §4.4)
/// - the faces and edges the active selection rule picks, which glow pink
public struct ViewportItem: Sendable {
    public var solid: Solid
    public var isGhost: Bool
    public var selectedFaces: Set<FaceID>
    public var selectedEdges: Set<EdgeID>

    public init(solid: Solid, isGhost: Bool = false, selectedFaces: Set<FaceID> = [], selectedEdges: Set<EdgeID> = []) {
        self.solid = solid
        self.isGhost = isGhost
        self.selectedFaces = selectedFaces
        self.selectedEdges = selectedEdges
    }
}

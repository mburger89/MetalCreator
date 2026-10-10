import CreatorKernel

/// One solid the viewport shows (spec §6.3). The host builds these from the document:
/// - output solids, and last-good results drawn as ghosts while their node is in error (spec §4.4)
/// - the faces and edges the active selection rule picks, which glow pink
/// - guides: the edges a selected rule picks on a solid the scene doesn't show, drawn over the part (`isGuide`)
public struct ViewportItem: Sendable {
    public var solid: Solid
    public var isGhost: Bool
    public var selectedFaces: Set<FaceID>
    public var selectedEdges: Set<EdgeID>
    /// A guide is not part of the scene (spec §6.3, Errata (M6)): it carries a solid the host doesn't show, and only
    /// its `selectedEdges` are drawn, in the selection colour, over the shown scene. They glow where they lie on a
    /// shown part and float free where they don't. A guide's surfaces and edges are otherwise never drawn, picked,
    /// hovered or offered in the face menu, and it never widens `sceneBounds` or the point the camera orbits about.
    public var isGuide: Bool

    public init(solid: Solid, isGhost: Bool = false, selectedFaces: Set<FaceID> = [], selectedEdges: Set<EdgeID> = [],
                isGuide: Bool = false) {
        self.solid = solid
        self.isGhost = isGhost
        self.selectedFaces = selectedFaces
        self.selectedEdges = selectedEdges
        self.isGuide = isGuide
    }
}

/// A selection of faces on one solid.
public struct FaceSet: Sendable {
    public var solid: Solid
    public var faces: [FaceID]

    public init(solid: Solid, faces: [FaceID]) {
        self.solid = solid
        self.faces = faces
    }
}

import CreatorKernel

/// A face of one shown solid (its index in `ViewportModel.items`).
public struct ViewportFaceRef: Hashable, Sendable {
    public var solidIndex: Int
    public var face: FaceID

    public init(solidIndex: Int, face: FaceID) {
        self.solidIndex = solidIndex
        self.face = face
    }
}

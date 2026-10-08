/// Per-solid data for the mesh fragment shaders.
struct DrawUniforms {
    /// `PickID.base` for this solid's faces (ID pass only).
    var pickBase: UInt32
    var ghost: UInt32
    /// Entries in the face-flags buffer.
    var faceCount: UInt32
    var padding: Float
}

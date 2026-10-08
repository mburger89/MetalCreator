import CreatorGeometry
import CreatorKernel

/// Where a ray first meets a displayed mesh.
struct RayHit: Equatable {
    var point: Vector3
    /// The ray parameter of the hit (negative is allowed for orthographic rays).
    var distance: Double
    var solidIndex: Int
    var face: FaceID
}

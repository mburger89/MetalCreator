/// The kind of a face's surface. `FaceInfo.kind` reads the first seven; `Kernel.surfaceInfo(of:in:)` tells apart the rest, which
/// `FaceInfo` reports as `.other`.
public enum SurfaceKind: String, Sendable, Codable {
    case plane, cylinder, cone, sphere, torus, bspline, other
    case bezier, revolution, extrusion, offset
}

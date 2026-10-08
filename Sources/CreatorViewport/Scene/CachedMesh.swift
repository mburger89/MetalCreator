import CreatorKernel

/// A tessellation with a serial number unique within its cache. The GPU caches meshes by serial, so a new mesh
/// (a new solid, or a new tolerance) can never be mistaken for an old one.
struct CachedMesh: Sendable {
    let serial: Int
    let mesh: DisplayMesh
}

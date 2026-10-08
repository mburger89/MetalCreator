/// One de-indexed triangle corner: position, normal and the face it belongs to.
struct MeshVertex: Equatable {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var face: UInt32
}

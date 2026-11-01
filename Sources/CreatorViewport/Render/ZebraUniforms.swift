import CreatorGeometry

/// The zebra's frame and settings for the shaders. Unlocked, `right`, `up` and `toEye` are the view axes and `params.w` is 0.
/// `params` is (stripes, black share, vertical 0 or 1, locked 0 or 1). Mirrors `ZebraUniforms` in the shaders (stride pinned by
/// `GPUDataTests`).
struct ZebraUniforms {
    var right: SIMD4<Float>
    var up: SIMD4<Float>
    var toEye: SIMD4<Float>
    var params: SIMD4<Float>

    init(_ zebra: ViewportZebra) {
        let frame = zebra.lock
        func lift(_ v: Vector3) -> SIMD4<Float> { SIMD4(Float(v.x), Float(v.y), Float(v.z), 0) }
        right = frame.map { lift($0.right) } ?? SIMD4(1, 0, 0, 0)
        up = frame.map { lift($0.up) } ?? SIMD4(0, 1, 0, 0)
        toEye = frame.map { lift($0.toEye) } ?? SIMD4(0, 0, 1, 0)
        params = SIMD4(Float(zebra.stripes), Float(zebra.blackShare), zebra.direction == .vertical ? 1 : 0,
                       frame == nil ? 0 : 1)
    }
}

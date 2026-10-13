import CreatorGeometry

/// The slice quad for its shaders: the centre, the half-extents as vectors (`across` is `xAxis × halfWidth`, `up` is
/// `yAxis × halfHeight`) and, in `style.x`, the opacity. Mirrors `SliceUniforms` in `FieldShaders` (stride pinned by
/// `ViewportSliceRenderTests`).
struct SliceUniforms {
    var origin: SIMD4<Float>
    var across: SIMD4<Float>
    var up: SIMD4<Float>
    var style: SIMD4<Float>

    init(_ slice: ViewportSlice) {
        let across = GPUGeometry.float3(slice.xAxis * slice.halfWidth)
        let up = GPUGeometry.float3(slice.yAxis * slice.halfHeight)
        origin = SIMD4(GPUGeometry.float3(slice.origin), 1)
        self.across = SIMD4(across, 0)
        self.up = SIMD4(up, 0)
        style = SIMD4(slice.opacity, 0, 0, 0)
    }
}

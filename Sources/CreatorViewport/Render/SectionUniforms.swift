/// One corner of a cap triangle (`SectionVertex` in `SectionShaders`, pinned by `GPUDataTests`): `xyz` is the position.
struct SectionVertex: Equatable {
    var position: SIMD4<Float>
}

/// One cap's draw settings for the shaders (`SectionUniforms` in `SectionShaders`, stride pinned by `GPUDataTests`).
/// - `origin`, `axisU` and `axisV` are the section plane's origin and axes, the hatch's frame.
/// - `hatchParams` is the spacing and line width (mm) and the cosine and sine of the hatch angle.
/// - `depthParams.x` is how far (mm) the cap's vertices move towards the eye so the cap wins against a coplanar face.
struct SectionUniforms: Equatable {
    var fill: SIMD4<Float>
    var hatch: SIMD4<Float>
    var origin: SIMD4<Float>
    var axisU: SIMD4<Float>
    var axisV: SIMD4<Float>
    var hatchParams: SIMD4<Float>
    var depthParams: SIMD4<Float>
}

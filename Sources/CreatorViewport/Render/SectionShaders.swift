/// The section cap's Metal shaders, appended to `ViewportShaders.source` when the library is compiled (`ViewportPipelines`), so
/// they may use its `FrameUniforms` and `ClipUniforms`. The structs mirror `SectionUniforms.swift` (strides pinned by `GPUDataTests`).
enum SectionShaders {
    static let source = """

struct SectionVertex { float4 position; };
struct SectionUniforms {
    float4 fill; float4 hatch; float4 origin; float4 axisU; float4 axisV; float4 hatchParams; float4 depthParams;
};

// MARK: Section cap

struct SectionOut {
    float4 position [[position]];
    float3 world;
};

// The cap's vertices move towards the eye so it wins against a face on its own plane; the clip test keeps the true position.
vertex SectionOut section_vertex(uint vid [[vertex_id]],
                                 device const SectionVertex *vertices [[buffer(0)]],
                                 constant FrameUniforms &uniforms [[buffer(1)]],
                                 constant SectionUniforms &section [[buffer(2)]]) {
    float3 p = vertices[vid].position.xyz;
    float3 toward = uniforms.isOrthographic != 0u ? -uniforms.forward : normalize(uniforms.eye - p);
    SectionOut out;
    out.position = uniforms.viewProjection * float4(p + toward * section.depthParams.x, 1.0);
    out.world = p;
    return out;
}

fragment float4 section_fragment(SectionOut in [[stage_in]],
                                 constant SectionUniforms &section [[buffer(0)]],
                                 constant ClipUniforms &clip [[buffer(1)]]) {
    if (clipped(clip, in.world)) {
        discard_fragment();
    }
    float3 d = in.world - section.origin.xyz;
    float s = dot(d, section.axisU.xyz) * section.hatchParams.z + dot(d, section.axisV.xyz) * section.hatchParams.w;
    float spacing = section.hatchParams.x;
    bool stripe = fract(s / spacing) < section.hatchParams.y / spacing;
    return stripe ? section.hatch : section.fill;
}

// The ID pass writes "nothing" (with depth) where the cap is, so a click on it never reaches the face behind it.
fragment uint id_section_fragment(SectionOut in [[stage_in]],
                                  constant ClipUniforms &clip [[buffer(1)]]) {
    if (clipped(clip, in.world)) {
        discard_fragment();
    }
    return 0u;
}
"""
}

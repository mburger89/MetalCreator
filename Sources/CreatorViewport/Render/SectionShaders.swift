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
    // Antialiased: the distance (mm) to the stripe's centre line, blended over a pixel's width of `s`.
    float centre = section.hatchParams.y / (2.0 * spacing);
    float across = abs(fract(s / spacing) - centre);
    float distance = min(across, 1.0 - across) * spacing;
    float half_width = section.hatchParams.y * 0.5;
    float soft = max(fwidth(s) * 0.5, 1e-6);
    float coverage = 1.0 - smoothstep(half_width - soft, half_width + soft, distance);
    return mix(section.fill, section.hatch, coverage);
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

/// The viewport's line shaders (B-rep edges, handles, the triad, the overlay), appended to `ViewportShaders.source` when the library is
/// compiled (`ViewportPipelines`), so they may use its `FrameUniforms`, `LineInstance`, `LineUniforms` and `ClipUniforms`. The cut view's
/// plane clips them in the fragment shader (buffer 0); a draw that is not cut binds `ClipUniforms.off`.
enum LineShaders {
    static let source = """

// MARK: Lines (B-rep edges, handles, the triad)

struct LineOut {
    float4 position [[position]];
    float across;
    float halfWidth [[flat]];
    float4 color [[flat]];
    uint id [[flat]];
    float3 world;
};

vertex LineOut line_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           device const LineInstance *lines [[buffer(0)]],
                           constant FrameUniforms &uniforms [[buffer(1)]],
                           constant LineUniforms &style [[buffer(2)]]) {
    LineInstance line = lines[iid];
    float3 a = line.a;
    float3 b = line.b;
    if (style.depthBias > 0.0) {
        float3 towardA = uniforms.isOrthographic != 0u ? -uniforms.forward : normalize(uniforms.eye - a);
        float3 towardB = uniforms.isOrthographic != 0u ? -uniforms.forward : normalize(uniforms.eye - b);
        a += towardA * style.depthBias;
        b += towardB * style.depthBias;
    }
    float4 clipA = uniforms.viewProjection * float4(a, 1.0);
    float4 clipB = uniforms.viewProjection * float4(b, 1.0);
    LineOut out;
    out.color = line.color;
    out.id = line.id;
    out.world = float3(0.0);
    float width = style.widthOverride > 0.0 ? style.widthOverride : line.width;
    out.halfWidth = width * 0.5;
    if (clipA.w <= 1e-6 || clipB.w <= 1e-6) {
        out.position = float4(0.0, 0.0, 2.0, 1.0);   // behind the eye: outside the clip volume
        out.across = 0.0;
        return out;
    }
    float2 halfViewport = 0.5 * uniforms.viewportPixels;
    float2 screenA = clipA.xy / clipA.w * halfViewport;
    float2 screenB = clipB.xy / clipB.w * halfViewport;
    float2 delta = screenB - screenA;
    float length = metal::length(delta);
    float2 along = length > 1e-4 ? delta / length : float2(1.0, 0.0);
    float2 normal = float2(-along.y, along.x);
    bool atB = (vid & 1u) != 0u;
    float side = (vid & 2u) != 0u ? 1.0 : -1.0;
    float reach = out.halfWidth + 1.0;
    float2 offset = normal * side * reach + along * (atB ? 1.0 : -1.0) * out.halfWidth;
    float4 clip = atB ? clipB : clipA;
    out.position = float4(clip.xy + offset / halfViewport * clip.w, clip.z, clip.w);
    out.across = side * reach;
    out.world = atB ? b : a;
    return out;
}

fragment float4 line_fragment(LineOut in [[stage_in]], constant ClipUniforms &clip [[buffer(0)]]) {
    if (clipped(clip, in.world)) {
        discard_fragment();
    }
    float coverage = saturate(in.halfWidth + 0.5 - abs(in.across));
    float alpha = in.color.a * coverage;
    return float4(in.color.rgb * alpha, alpha);
}

fragment uint id_line_fragment(LineOut in [[stage_in]], constant ClipUniforms &clip [[buffer(0)]]) {
    if (clipped(clip, in.world) || abs(in.across) > in.halfWidth) {
        discard_fragment();
    }
    return in.id;
}
"""
}

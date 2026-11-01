/// The viewport's zebra-stripe shaders (the zebra spec, plan Ruling 1), appended to `ViewportShaders.source` when the library is
/// compiled (`ViewportPipelines`), so they may use its `MeshVertex`, `FrameUniforms`, `DrawUniforms`, `ShadeUniforms` and
/// `ClipUniforms`. `ZebraUniforms` mirrors the Swift struct (stride pinned by `GPUDataTests`); `ZebraBand.value` is the CPU twin of
/// `zebra_band`.
enum ZebraShaders {
    static let source = """

struct ZebraUniforms { float4 right; float4 up; float4 toEye; float4 params; };

struct ZebraOut {
    float4 position [[position]];
    float3 viewNormal;
    float3 worldNormal;
    float3 viewPosition;
    float3 world;
    uint face [[flat]];
    uint orthographic [[flat]];
};

vertex ZebraOut zebra_mesh_vertex(uint vid [[vertex_id]],
                                  device const MeshVertex *vertices [[buffer(0)]],
                                  constant FrameUniforms &uniforms [[buffer(1)]]) {
    MeshVertex v = vertices[vid];
    ZebraOut out;
    out.position = uniforms.viewProjection * float4(v.position, 1.0);
    out.viewNormal = (uniforms.view * float4(v.normal, 0.0)).xyz;
    out.worldNormal = v.normal;
    out.viewPosition = (uniforms.view * float4(v.position, 1.0)).xyz;
    out.world = v.position;
    out.face = v.face;
    out.orthographic = uniforms.isOrthographic;
    return out;
}

// The stripe phase p = theta * count / 2pi of the reflection r = 2(n.v)n - v, theta measured in the view's axes (unlocked) or the
// lock frame's (locked). Black when fract(p) < blackShare. Returns 0 for black, 1 for white, antialiased over fwidth(p).
float zebra_band(constant ZebraUniforms &zebra, float3 nView, float3 nWorld, float3 viewPosition, bool orthographic) {
    bool locked = zebra.params.w != 0.0;
    float3 n = locked ? nWorld : nView;
    float3 v = locked ? normalize(zebra.toEye.xyz)
                      : (orthographic ? float3(0.0, 0.0, 1.0) : -normalize(viewPosition));
    float3 r = 2.0 * dot(n, v) * n - v;
    float3 axes = locked ? float3(dot(r, zebra.right.xyz), dot(r, zebra.up.xyz), dot(r, zebra.toEye.xyz)) : r;
    float across = zebra.params.z != 0.0 ? axes.x : axes.y;
    float p = atan2(across, axes.z) * zebra.params.x / 6.2831853;
    float f = fract(p);
    // The angle's seam is a whole number of periods apart, so fract is continuous there but fwidth is not: clamp it.
    float h = 0.5 * min(fwidth(p), 0.25);
    float share = zebra.params.y;
    return smoothstep(share - h, share + h, f) * (1.0 - smoothstep(1.0 - h, 1.0, f));
}

fragment float4 zebra_mesh_fragment(ZebraOut in [[stage_in]],
                                    constant DrawUniforms &draw [[buffer(0)]],
                                    device const uint *faceFlags [[buffer(1)]],
                                    constant ShadeUniforms &shade [[buffer(2)]],
                                    constant ClipUniforms &clip [[buffer(3)]],
                                    constant ZebraUniforms &zebra [[buffer(4)]],
                                    bool front [[front_facing]]) {
    if (clipped(clip, in.world)) {
        discard_fragment();
    }
    // A back face seen through a cut is striped with its normal flipped.
    float side = front ? 1.0 : -1.0;
    float3 nView = normalize(in.viewNormal) * side;
    float3 nWorld = normalize(in.worldNormal) * side;
    float band = zebra_band(zebra, nView, nWorld, in.viewPosition, in.orthographic != 0u);
    float3 key = normalize(float3(-0.4, 0.7, 0.6));
    float lit = 0.8 + 0.2 * saturate(dot(nView, key));
    float3 color = mix(shade.dark.rgb * 0.15, shade.light.rgb, band) * lit;
    uint flags = in.face < draw.faceCount ? faceFlags[in.face] : 0u;
    if ((flags & 2u) != 0u) {
        color = mix(color, shade.selection.rgb, 0.55);
    } else if ((flags & 1u) != 0u) {
        color = mix(color, shade.hover.rgb, 0.18);
    }
    if ((flags & 4u) != 0u) {
        color = mix(color, shade.warning.rgb, 0.7);
    }
    return float4(saturate(color), 1.0);
}
"""
}

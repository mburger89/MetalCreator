/// The viewport's field-preview shaders (fields spec section 6), appended to `ViewportShaders.source` when the library is
/// compiled (`ViewportPipelines`), so they may use its `MeshVertex`, `FrameUniforms`, `DrawUniforms` and `ShadeUniforms`. The
/// structs here mirror the Swift ones in this folder (strides pinned by `FieldTintDataTests`).
enum FieldShaders {
    static let source = """

struct FieldRampUniforms { float4 low; float4 mid; float4 high; float4 range; };

// MARK: Field tint: the surface coloured by a value per corner

struct FieldOut {
    float4 position [[position]];
    float3 viewNormal;
    uint face [[flat]];
    float value;
};

vertex FieldOut field_mesh_vertex(uint vid [[vertex_id]],
                                  device const MeshVertex *vertices [[buffer(0)]],
                                  constant FrameUniforms &uniforms [[buffer(1)]],
                                  device const float *values [[buffer(2)]]) {
    MeshVertex v = vertices[vid];
    FieldOut out;
    out.position = uniforms.viewProjection * float4(v.position, 1.0);
    out.viewNormal = (uniforms.view * float4(v.normal, 0.0)).xyz;
    out.face = v.face;
    out.value = values[vid];
    return out;
}

// FieldRamp.color(at:) in Swift: low to mid up to the middle value, mid to high above it, held beyond the ends.
float3 field_ramp(constant FieldRampUniforms &ramp, float value) {
    if (value <= ramp.range.y) {
        float span = ramp.range.y - ramp.range.x;
        float t = span > 0.0 ? saturate((value - ramp.range.x) / span) : 1.0;
        return mix(ramp.low.rgb, ramp.mid.rgb, t);
    }
    float span = ramp.range.z - ramp.range.y;
    float t = span > 0.0 ? saturate((value - ramp.range.y) / span) : 1.0;
    return mix(ramp.mid.rgb, ramp.high.rgb, t);
}

fragment float4 field_mesh_fragment(FieldOut in [[stage_in]],
                                    constant DrawUniforms &draw [[buffer(0)]],
                                    device const uint *faceFlags [[buffer(1)]],
                                    constant ShadeUniforms &shade [[buffer(2)]],
                                    constant FieldRampUniforms &ramp [[buffer(3)]]) {
    float3 n = normalize(in.viewNormal);
    float3 key = normalize(float3(-0.4, 0.7, 0.6));
    float diffuse = saturate(dot(n, key));
    float rim = pow(1.0 - saturate(n.z), 2.0);
    float lit = saturate(0.15 + 0.75 * diffuse + 0.1 * n.y);
    float3 color = field_ramp(ramp, in.value) * (0.55 + 0.45 * lit) + rim * 0.06;
    uint flags = in.face < draw.faceCount ? faceFlags[in.face] : 0u;
    if ((flags & 2u) != 0u) {
        color = mix(color, shade.selection.rgb, 0.55);
    } else if ((flags & 1u) != 0u) {
        color = mix(color, shade.hover.rgb, 0.18);
    }
    return float4(saturate(color), 1.0);
}
"""
}

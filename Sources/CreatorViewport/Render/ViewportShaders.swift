/// The viewport's Metal shaders, compiled at runtime with `makeLibrary(source:)` (no `.metal` build step, as in
/// MetalUI's own demo). The structs mirror the Swift ones in this folder. `GPUDataTests` pins their strides.
enum ViewportShaders {
    static let source = """
#include <metal_stdlib>
using namespace metal;

// Mirrors of the Swift structs in Sources/CreatorViewport/Render (strides pinned by GPUDataTests).
struct FrameUniforms {
    float4x4 viewProjection;
    float4x4 view;
    float3 eye;
    float3 forward;
    float2 viewportPixels;
    uint isOrthographic;
    float padding;
};
struct MeshVertex { float3 position; float3 normal; uint face; };
struct DrawUniforms { uint pickBase; uint ghost; uint faceCount; float padding; };
struct ShadeUniforms { float4 light; float4 dark; float4 hover; float4 selection; float4 warning; };
struct BackgroundUniforms { float4 top; float4 bottom; };
struct LineInstance { float3 a; float3 b; float4 color; float width; uint id; };
struct LineUniforms { float widthOverride; float depthBias; float padding0; float padding1; };
struct GridUniforms { float2 center; float extent; float spacing; float4 minorColor; float4 majorColor; };
struct CubeVertex { float3 position; float4 color; float2 uv; float4 labelRect; };
struct FillVertex { float3 position; float4 color; };
// The cut view's plane: a point is cut away when dot(plane.xyz, p) + plane.w > 0.
struct ClipUniforms { float4 plane; uint enabled; uint padding0; uint padding1; uint padding2; };

bool clipped(constant ClipUniforms &clip, float3 world) {
    return clip.enabled != 0u && dot(clip.plane.xyz, world) + clip.plane.w > 0.0;
}

// MARK: Background

struct BackgroundOut { float4 position [[position]]; float v; };

vertex BackgroundOut background_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(vid == 1u ? 3.0 : -1.0, vid == 2u ? 3.0 : -1.0);
    BackgroundOut out;
    out.position = float4(p, 0.0, 1.0);
    out.v = (1.0 - p.y) * 0.5;
    return out;
}

fragment float4 background_fragment(BackgroundOut in [[stage_in]],
                                    constant BackgroundUniforms &colors [[buffer(0)]]) {
    return float4(mix(colors.top.rgb, colors.bottom.rgb, saturate(in.v)), 1.0);
}

// MARK: Solids

struct MeshOut {
    float4 position [[position]];
    float3 viewNormal;
    float3 world;
    uint face [[flat]];
};

vertex MeshOut mesh_vertex(uint vid [[vertex_id]],
                           device const MeshVertex *vertices [[buffer(0)]],
                           constant FrameUniforms &uniforms [[buffer(1)]]) {
    MeshVertex v = vertices[vid];
    MeshOut out;
    out.position = uniforms.viewProjection * float4(v.position, 1.0);
    out.viewNormal = (uniforms.view * float4(v.normal, 0.0)).xyz;
    out.face = v.face;
    out.world = v.position;
    return out;
}

fragment float4 mesh_fragment(MeshOut in [[stage_in]],
                              constant DrawUniforms &draw [[buffer(0)]],
                              device const uint *faceFlags [[buffer(1)]],
                              constant ShadeUniforms &shade [[buffer(2)]],
                              constant ClipUniforms &clip [[buffer(3)]],
                              bool front [[front_facing]]) {
    if (clipped(clip, in.world)) {
        discard_fragment();
    }
    float3 n = normalize(in.viewNormal);
    float3 key = normalize(float3(-0.4, 0.7, 0.6));
    float diffuse = saturate(dot(n, key));
    float rim = pow(1.0 - saturate(n.z), 2.0);
    float t = saturate(0.15 + 0.75 * diffuse + 0.1 * n.y);
    float3 color = mix(shade.dark.rgb, shade.light.rgb, t) + rim * 0.06;
    uint flags = in.face < draw.faceCount ? faceFlags[in.face] : 0u;
    if ((flags & 2u) != 0u) {
        color = mix(color, shade.selection.rgb, 0.55);
    } else if ((flags & 1u) != 0u) {
        color = mix(color, shade.hover.rgb, 0.18);
    }
    if ((flags & 4u) != 0u) {
        color = mix(color, shade.warning.rgb, 0.7);
    }
    // Looking into a cut part, the inside of its far wall stands for the cut face: the part's colour, darkened and flat.
    if (clip.enabled != 0u && !front) {
        color = mix(shade.dark.rgb, shade.light.rgb, 0.5) * 0.55;
    }
    color = saturate(color);
    if (draw.ghost != 0u) {
        float grey = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(color, float3(grey), 0.85);
        return float4(color * 0.4, 0.4);
    }
    return float4(color, 1.0);
}

fragment uint id_mesh_fragment(MeshOut in [[stage_in]], constant DrawUniforms &draw [[buffer(0)]],
                               constant ClipUniforms &clip [[buffer(3)]]) {
    if (clipped(clip, in.world)) {
        discard_fragment();
    }
    return draw.pickBase | in.face;
}



// MARK: Ground grid

struct GridOut { float4 position [[position]]; float2 world; };

vertex GridOut grid_vertex(uint vid [[vertex_id]],
                           constant FrameUniforms &uniforms [[buffer(1)]],
                           constant GridUniforms &grid [[buffer(2)]]) {
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : -1.0, (vid & 2u) != 0u ? 1.0 : -1.0);
    float2 world = grid.center + corner * grid.extent * 0.5;
    GridOut out;
    out.position = uniforms.viewProjection * float4(world, 0.0, 1.0);
    out.world = world;
    return out;
}

fragment float4 grid_fragment(GridOut in [[stage_in]], constant GridUniforms &grid [[buffer(2)]]) {
    float2 minorCoord = in.world / grid.spacing;
    float2 minorCell = abs(fract(minorCoord - 0.5) - 0.5) / max(fwidth(minorCoord), float2(1e-6));
    float minor = 1.0 - saturate(min(minorCell.x, minorCell.y));
    float2 majorCoord = in.world / (grid.spacing * 10.0);
    float2 majorCell = abs(fract(majorCoord - 0.5) - 0.5) / max(fwidth(majorCoord), float2(1e-6));
    float major = 1.0 - saturate(min(majorCell.x, majorCell.y));
    float fade = 1.0 - saturate(metal::length(in.world - grid.center) / (grid.extent * 0.5));
    float alpha = max(minor * 0.35, major * 0.6) * fade;
    float3 color = mix(grid.minorColor.rgb, grid.majorColor.rgb, major);
    return float4(color * alpha, alpha);
}

// MARK: Overlay fills (a sketch region's faint colour, under the overlay's lines)

struct FillOut {
    float4 position [[position]];
    float4 color [[flat]];
};

vertex FillOut fill_vertex(uint vid [[vertex_id]],
                           device const FillVertex *vertices [[buffer(0)]],
                           constant FrameUniforms &uniforms [[buffer(1)]]) {
    FillVertex v = vertices[vid];
    FillOut out;
    out.position = uniforms.viewProjection * float4(v.position, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 fill_fragment(FillOut in [[stage_in]]) {
    return float4(in.color.rgb * in.color.a, in.color.a);
}

// MARK: View cube

struct CubeOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
    float4 labelRect [[flat]];
};

vertex CubeOut cube_vertex(uint vid [[vertex_id]],
                           device const CubeVertex *vertices [[buffer(0)]],
                           constant FrameUniforms &uniforms [[buffer(1)]]) {
    CubeVertex v = vertices[vid];
    CubeOut out;
    out.position = uniforms.viewProjection * float4(v.position, 1.0);
    out.color = v.color;
    out.uv = v.uv;
    out.labelRect = v.labelRect;
    return out;
}

// The face's name, from the label atlas (r8 coverage, mipmapped), blended in `ink` over the tile's colour (hover
// and active cyan included). uv 0...1 is the text box. Outside it, or with an empty rect, there is no ink. The
// gradient is taken before clamping to the rect, so the mip level stays smooth up to the box's edge.
fragment float4 cube_fragment(CubeOut in [[stage_in]],
                              constant float4 &ink [[buffer(0)]],
                              texture2d<float> labels [[texture(0)]]) {
    constexpr sampler atlas(filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(8));
    float2 atlasUV = mix(in.labelRect.xy, in.labelRect.zw, in.uv);
    float2 inRect = clamp(atlasUV, in.labelRect.xy, in.labelRect.zw);
    float coverage = labels.sample(atlas, inRect, gradient2d(dfdx(atlasUV), dfdy(atlasUV))).r;
    bool inside = all(in.uv >= 0.0) && all(in.uv <= 1.0) && in.labelRect.z > in.labelRect.x;
    float3 rgb = mix(in.color.rgb, ink.rgb, inside ? coverage * ink.a : 0.0);
    return float4(rgb * in.color.a, in.color.a);
}
"""
}

#include "common.hlsli"

cbuffer Draw : register(b0, space3) { DrawUniforms draw; };
cbuffer Shade : register(b1, space3) { ShadeUniforms shade; };
cbuffer Clip : register(b2, space3) { ClipUniforms clip; };
cbuffer Zebra : register(b3, space3) { ZebraUniforms zebra; };

struct In {
    float4 position : SV_Position;
    float3 viewNormal : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float3 viewPosition : TEXCOORD2;
    float3 world : TEXCOORD3;
    nointerpolation uint flags : TEXCOORD4;
    nointerpolation uint orthographic : TEXCOORD5;
};

// The HLSL twin of `zebra_band` in ZebraShaders.swift (keep them together). The stripe phase p = theta * count / 2pi of the reflection
// r = 2(n.v)n - v, theta measured in the view's axes (unlocked) or the lock frame's (locked). Black when fract(p) < blackShare.
// Returns 0 for black, 1 for white, antialiased over fwidth(p).
float zebraBand(float3 nView, float3 nWorld, float3 viewPosition, bool orthographic) {
    bool locked = zebra.params.w != 0.0;
    float3 n = locked ? nWorld : nView;
    float3 v = locked ? normalize(zebra.toEye.xyz)
                      : (orthographic ? float3(0.0, 0.0, 1.0) : -normalize(viewPosition));
    float3 r = 2.0 * dot(n, v) * n - v;
    float3 axes = locked ? float3(dot(r, zebra.right.xyz), dot(r, zebra.up.xyz), dot(r, zebra.toEye.xyz)) : r;
    float across = zebra.params.z != 0.0 ? axes.x : axes.y;
    float p = atan2(across, axes.z) * zebra.params.x / 6.2831853;
    float f = frac(p);
    // The angle's seam is a whole number of periods apart, so frac is continuous there but fwidth is not: clamp it. A flat face seen
    // orthographically has fwidth 0, which would leave the smoothstep's edges equal, so the floor keeps them apart.
    float h = 0.5 * clamp(fwidth(p), 1e-4, 0.25);
    float share = zebra.params.y;
    // The signed distance to the nearest edge of the black interval [0, share) on the circle of f: positive inside white.
    float s = f >= share ? min(f - share, 1.0 - f) : -min(f, share - f);
    return smoothstep(-h, h, s);
}

float4 main(In input, bool front : SV_IsFrontFace) : SV_Target0 {
    if (clipped(clip, input.world)) {
        discard;
    }
    // A back face seen through a cut is striped with its normal flipped.
    float side = front ? 1.0 : -1.0;
    float3 nView = normalize(input.viewNormal) * side;
    float3 nWorld = normalize(input.worldNormal) * side;
    float band = zebraBand(nView, nWorld, input.viewPosition, input.orthographic != 0u);
    float3 key = normalize(float3(-0.4, 0.7, 0.6));
    float lit = 0.8 + 0.2 * saturate(dot(nView, key));
    float3 color = lerp(shade.dark.rgb * 0.15, shade.light.rgb, band) * lit;
    uint flags = input.flags;
    if ((flags & 2u) != 0u) {
        color = lerp(color, shade.selection.rgb, 0.55);
    } else if ((flags & 1u) != 0u) {
        color = lerp(color, shade.hover.rgb, 0.18);
    }
    if ((flags & 4u) != 0u) {
        color = lerp(color, shade.warning.rgb, 0.7);
    }
    // A ghost is never striped; the draw uniform is read so the compiler keeps its buffer, which SDL_GPU binds by count from slot 0:
    // dropping an unused b0 would shift the others' slots (the vertex stage reads the face count).
    // Reads draw.ghost so b0 stays bound (MetalUI XP-G36, our gap XP-G28); ghosts never reach this shader (the MSL always writes 1).
    return float4(saturate(color), draw.ghost != 0u ? 0.4 : 1.0);
}

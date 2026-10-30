#include "common.hlsli"

cbuffer Draw : register(b0, space3) { DrawUniforms draw; };
cbuffer Shade : register(b1, space3) { ShadeUniforms shade; };
cbuffer Clip : register(b2, space3) { ClipUniforms clip; };

struct In {
    float4 position : SV_Position;
    float3 viewNormal : TEXCOORD0;
    float3 world : TEXCOORD1;
    nointerpolation uint flags : TEXCOORD2;
};

float4 main(In input, bool front : SV_IsFrontFace) : SV_Target0 {
    if (clipped(clip, input.world)) {
        discard;
    }
    float3 n = normalize(input.viewNormal);
    float3 key = normalize(float3(-0.4, 0.7, 0.6));
    float diffuse = saturate(dot(n, key));
    float rim = pow(1.0 - saturate(n.z), 2.0);
    float t = saturate(0.15 + 0.75 * diffuse + 0.1 * n.y);
    float3 color = lerp(shade.dark.rgb, shade.light.rgb, t) + rim * 0.06;
    uint flags = input.flags;
    if ((flags & 2u) != 0u) {
        color = lerp(color, shade.selection.rgb, 0.55);
    } else if ((flags & 1u) != 0u) {
        color = lerp(color, shade.hover.rgb, 0.18);
    }
    if ((flags & 4u) != 0u) {
        color = lerp(color, shade.warning.rgb, 0.7);
    }
    // Looking into a cut part, the inside of its far wall stands for the cut face: the part's colour, darkened and flat.
    if (clip.enabled.x != 0u && !front) {
        color = lerp(shade.dark.rgb, shade.light.rgb, 0.5) * 0.55;
    }
    color = saturate(color);
    if (draw.ghost != 0u) {
        float grey = dot(color, float3(0.299, 0.587, 0.114));
        color = lerp(color, float3(grey, grey, grey), 0.85);
        return float4(color * 0.4, 0.4);
    }
    return float4(color, 1.0);
}

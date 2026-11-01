#include "common.hlsli"

cbuffer Shade : register(b0, space3) { ShadeUniforms shade; };
cbuffer Ramp : register(b1, space3) { FieldRampUniforms ramp; };
cbuffer Clip : register(b2, space3) { ClipUniforms clip; };

struct In {
    float4 position : SV_Position;
    float3 viewNormal : TEXCOORD0;
    float3 world : TEXCOORD1;
    nointerpolation uint flags : TEXCOORD2;
    float value : TEXCOORD3;
};

float4 main(In input) : SV_Target0 {
    if (clipped(clip, input.world)) {
        discard;
    }
    float3 n = normalize(input.viewNormal);
    float3 key = normalize(float3(-0.4, 0.7, 0.6));
    float diffuse = saturate(dot(n, key));
    float rim = pow(1.0 - saturate(n.z), 2.0);
    float lit = saturate(0.15 + 0.75 * diffuse + 0.1 * n.y);
    float3 color = fieldRamp(ramp, input.value) * (0.55 + 0.45 * lit) + rim * 0.06;
    uint flags = input.flags;
    if ((flags & 2u) != 0u) {
        color = lerp(color, shade.selection.rgb, 0.55);
    } else if ((flags & 1u) != 0u) {
        color = lerp(color, shade.hover.rgb, 0.18);
    }
    return float4(saturate(color), 1.0);
}

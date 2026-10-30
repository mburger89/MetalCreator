#include "common.hlsli"

cbuffer Clip : register(b0, space3) { ClipUniforms clip; };

struct In {
    float4 position : SV_Position;
    float across : TEXCOORD0;
    nointerpolation float halfWidth : TEXCOORD1;
    nointerpolation float4 color : TEXCOORD2;
    float3 world : TEXCOORD3;
};

float4 main(In input) : SV_Target0 {
    if (clipped(clip, input.world)) {
        discard;
    }
    float coverage = saturate(input.halfWidth + 0.5 - abs(input.across));
    float alpha = input.color.a * coverage;
    return float4(input.color.rgb * alpha, alpha);
}

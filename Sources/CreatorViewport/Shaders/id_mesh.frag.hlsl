#include "common.hlsli"

cbuffer Clip : register(b0, space3) { ClipUniforms clip; };

struct In {
    float4 position : SV_Position;
    float3 world : TEXCOORD0;
    nointerpolation uint id : TEXCOORD1;
};

uint main(In input) : SV_Target0 {
    if (clipped(clip, input.world)) {
        discard;
    }
    return input.id;
}

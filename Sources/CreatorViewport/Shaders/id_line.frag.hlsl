#include "common.hlsli"

cbuffer Clip : register(b0, space3) { ClipUniforms clip; };

struct In {
    float4 position : SV_Position;
    float across : TEXCOORD0;
    nointerpolation float halfWidth : TEXCOORD1;
    nointerpolation uint id : TEXCOORD2;
    float3 world : TEXCOORD3;
};

uint main(In input) : SV_Target0 {
    if (clipped(clip, input.world) || abs(input.across) > input.halfWidth) {
        discard;
    }
    return input.id;
}

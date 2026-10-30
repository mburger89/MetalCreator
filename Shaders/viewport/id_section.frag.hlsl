#include "common.hlsli"

// The ID pass writes "nothing" (0, with depth) where the cap is, so a click on it never reaches the face behind it.
cbuffer Clip : register(b0, space3) { ClipUniforms clip; };

uint main(float4 position : SV_Position, float3 world : TEXCOORD0) : SV_Target0 {
    if (clipped(clip, world)) {
        discard;
    }
    return 0u;
}

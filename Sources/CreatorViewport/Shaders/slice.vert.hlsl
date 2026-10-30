#include "common.hlsli"

// The field slice: a translucent quad, four vertices as a strip.
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Slice : register(b1, space1) { SliceUniforms slice; };

struct Out {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

Out main(uint vid : SV_VertexID) {
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : 0.0, (vid & 2u) != 0u ? 1.0 : 0.0);
    float3 world = slice.origin.xyz + slice.across.xyz * (2.0 * corner.x - 1.0) + slice.up.xyz * (2.0 * corner.y - 1.0);
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(world, 1.0));
    output.uv = corner;
    return output;
}

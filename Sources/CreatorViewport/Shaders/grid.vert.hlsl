#include "common.hlsli"

// The ground grid: a square on z = 0, four vertices as a strip.
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Grid : register(b1, space1) { GridUniforms grid; };

struct Out {
    float4 position : SV_Position;
    float2 world : TEXCOORD0;
};

Out main(uint vid : SV_VertexID) {
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : -1.0, (vid & 2u) != 0u ? 1.0 : -1.0);
    float2 world = grid.centerExtentSpacing.xy + corner * grid.centerExtentSpacing.z * 0.5;
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(world, 0.0, 1.0));
    output.world = world;
    return output;
}

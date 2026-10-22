#include "common.hlsli"

// Overlay fills (a sketch region's faint colour, under the overlay's lines).
StructuredBuffer<FillVertex> vertices : register(t0, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };

struct Out {
    float4 position : SV_Position;
    nointerpolation float4 color : TEXCOORD0;
};

Out main(uint vid : SV_VertexID) {
    FillVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.color = v.color;
    return output;
}

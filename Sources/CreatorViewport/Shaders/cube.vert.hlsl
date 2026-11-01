#include "common.hlsli"

// The view cube: two triangles per tile, in the viewport the renderer sets for it.
StructuredBuffer<CubeVertex> vertices : register(t0, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };

struct Out {
    float4 position : SV_Position;
    float4 color : TEXCOORD0;
    float2 uv : TEXCOORD1;
    nointerpolation float4 labelRect : TEXCOORD2;
};

Out main(uint vid : SV_VertexID) {
    CubeVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.color = v.color;
    output.uv = v.uv;
    output.labelRect = v.labelRect;
    return output;
}

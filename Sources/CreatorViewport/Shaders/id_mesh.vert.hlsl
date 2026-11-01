#include "common.hlsli"

// The ID pass's solids: the pick ID of the corner's face (`pickBase | face`) reaches the fragment stage as a flat uint.
StructuredBuffer<MeshVertex> vertices : register(t0, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Draw : register(b1, space1) { DrawUniforms draw; };

struct Out {
    float4 position : SV_Position;
    float3 world : TEXCOORD0;
    nointerpolation uint id : TEXCOORD1;
};

Out main(uint vid : SV_VertexID) {
    MeshVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.world = v.position.xyz;
    output.id = draw.pickBase | v.face.x;
    return output;
}

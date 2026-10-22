#include "common.hlsli"

// The surface coloured by a value per corner (fields spec section 6): `mesh.vert` plus the value.
StructuredBuffer<MeshVertex> vertices : register(t0, space0);
StructuredBuffer<uint> faceFlags : register(t1, space0);
StructuredBuffer<float> values : register(t2, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Draw : register(b1, space1) { DrawUniforms draw; };

struct Out {
    float4 position : SV_Position;
    float3 viewNormal : TEXCOORD0;
    float3 world : TEXCOORD1;
    nointerpolation uint flags : TEXCOORD2;
    float value : TEXCOORD3;
};

Out main(uint vid : SV_VertexID) {
    MeshVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.viewNormal = mulColumns(frame.view, float4(v.normal.xyz, 0.0)).xyz;
    output.world = v.position.xyz;
    output.flags = v.face.x < draw.faceCount ? faceFlags[v.face.x] : 0u;
    output.value = values[vid];
    return output;
}

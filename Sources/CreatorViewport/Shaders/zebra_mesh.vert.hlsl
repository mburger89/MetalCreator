#include "common.hlsli"

// Zebra stripes (the zebra plan, Ruling 1): `mesh.vert` plus what the stripes need, the view-space position, the world and view
// normals and whether the camera is orthographic. The face flags are read here for the reason `mesh.vert` gives.
StructuredBuffer<MeshVertex> vertices : register(t0, space0);
StructuredBuffer<uint> faceFlags : register(t1, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Draw : register(b1, space1) { DrawUniforms draw; };

struct Out {
    float4 position : SV_Position;
    float3 viewNormal : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float3 viewPosition : TEXCOORD2;
    float3 world : TEXCOORD3;
    nointerpolation uint flags : TEXCOORD4;
    nointerpolation uint orthographic : TEXCOORD5;
};

Out main(uint vid : SV_VertexID) {
    MeshVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.viewNormal = mulColumns(frame.view, float4(v.normal.xyz, 0.0)).xyz;
    output.worldNormal = v.normal.xyz;
    output.viewPosition = mulColumns(frame.view, float4(v.position.xyz, 1.0)).xyz;
    output.world = v.position.xyz;
    output.flags = v.face.x < draw.faceCount ? faceFlags[v.face.x] : 0u;
    output.orthographic = asuint(frame.tail.z);
    return output;
}

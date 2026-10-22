#include "common.hlsli"

// Solids. The face flags are read here and not in the fragment stage: SDL_GPU's render pass binds storage buffers to the vertex stage
// only, and a flag is the same for every corner of a face, so a flat interpolant carries it to the fragment stage.
StructuredBuffer<MeshVertex> vertices : register(t0, space0);
StructuredBuffer<uint> faceFlags : register(t1, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Draw : register(b1, space1) { DrawUniforms draw; };

struct Out {
    float4 position : SV_Position;
    float3 viewNormal : TEXCOORD0;
    float3 world : TEXCOORD1;
    nointerpolation uint flags : TEXCOORD2;
};

Out main(uint vid : SV_VertexID) {
    MeshVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.viewNormal = mulColumns(frame.view, float4(v.normal.xyz, 0.0)).xyz;
    output.world = v.position.xyz;
    output.flags = v.face.x < draw.faceCount ? faceFlags[v.face.x] : 0u;
    return output;
}

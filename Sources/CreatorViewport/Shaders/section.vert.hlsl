#include "common.hlsli"

// The section cap: triangles read from a storage buffer. The vertices move towards the eye so the cap wins against a face on its own
// plane; the clip test keeps the true position.
StructuredBuffer<SectionVertex> vertices : register(t0, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Section : register(b1, space1) { SectionUniforms section; };

struct Out {
    float4 position : SV_Position;
    float3 world : TEXCOORD0;
};

Out main(uint vid : SV_VertexID) {
    float3 p = vertices[vid].position.xyz;
    bool isOrthographic = asuint(frame.tail.z) != 0u;
    float3 toward = isOrthographic ? -frame.forward.xyz : normalize(frame.eye.xyz - p);
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(p + toward * section.depthParams.x, 1.0));
    output.world = p;
    return output;
}

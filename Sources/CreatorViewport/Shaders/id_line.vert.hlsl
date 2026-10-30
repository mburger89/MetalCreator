#include "common.hlsli"

// The ID pass's lines: `line.vert` with the edge's pick ID in place of its colour. Always the whole target.
StructuredBuffer<LineInstance> lines : register(t0, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Style : register(b1, space1) { LineUniforms style; };

struct Out {
    float4 position : SV_Position;
    float across : TEXCOORD0;
    nointerpolation float halfWidth : TEXCOORD1;
    nointerpolation uint id : TEXCOORD2;
    float3 world : TEXCOORD3;
};

Out main(uint vid : SV_VertexID, uint iid : SV_InstanceID) {
    LineInstance instance = lines[iid];
    float3 a = instance.a.xyz;
    float3 b = instance.b.xyz;
    bool isOrthographic = asuint(frame.tail.z) != 0u;
    if (style.depthBias > 0.0) {
        float3 towardA = isOrthographic ? -frame.forward.xyz : normalize(frame.eye.xyz - a);
        float3 towardB = isOrthographic ? -frame.forward.xyz : normalize(frame.eye.xyz - b);
        a += towardA * style.depthBias;
        b += towardB * style.depthBias;
    }
    float4 clipA = mulColumns(frame.viewProjection, float4(a, 1.0));
    float4 clipB = mulColumns(frame.viewProjection, float4(b, 1.0));
    Out output;
    output.id = instance.id;
    output.world = float3(0.0, 0.0, 0.0);
    float width = style.widthOverride > 0.0 ? style.widthOverride : instance.width;
    output.halfWidth = width * 0.5;
    if (clipA.w <= 1e-6 || clipB.w <= 1e-6) {
        output.position = float4(0.0, 0.0, 2.0, 1.0);
        output.across = 0.0;
        return output;
    }
    float2 halfViewport = 0.5 * frame.tail.xy;
    float2 screenA = clipA.xy / clipA.w * halfViewport;
    float2 screenB = clipB.xy / clipB.w * halfViewport;
    float2 delta = screenB - screenA;
    float segmentLength = length(delta);
    float2 along = segmentLength > 1e-4 ? delta / segmentLength : float2(1.0, 0.0);
    float2 normal = float2(-along.y, along.x);
    bool atB = (vid & 1u) != 0u;
    float side = (vid & 2u) != 0u ? 1.0 : -1.0;
    float reach = output.halfWidth + 1.0;
    float2 offset = normal * side * reach + along * (atB ? 1.0 : -1.0) * output.halfWidth;
    float4 clip = atB ? clipB : clipA;
    output.position = float4(clip.xy + offset / halfViewport * clip.w, clip.z, clip.w);
    output.across = side * reach;
    output.world = atB ? b : a;
    return output;
}

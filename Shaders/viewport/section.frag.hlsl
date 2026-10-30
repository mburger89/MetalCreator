#include "common.hlsli"

cbuffer Section : register(b0, space3) { SectionUniforms section; };
cbuffer Clip : register(b1, space3) { ClipUniforms clip; };

// Plane-space stripes: the position along the hatch direction, a line every `spacing` mm.
float4 main(float4 position : SV_Position, float3 world : TEXCOORD0) : SV_Target0 {
    if (clipped(clip, world)) {
        discard;
    }
    float3 d = world - section.origin.xyz;
    float s = dot(d, section.axisU.xyz) * section.hatchParams.z + dot(d, section.axisV.xyz) * section.hatchParams.w;
    float spacing = section.hatchParams.x;
    bool stripe = frac(s / spacing) < section.hatchParams.y / spacing;
    return stripe ? section.hatch : section.fill;
}

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
    // Antialiased: the distance (mm) to the stripe's centre line, blended over a pixel's width of `s`.
    float centre = section.hatchParams.y / (2.0 * spacing);
    float across = abs(frac(s / spacing) - centre);
    float distance = min(across, 1.0 - across) * spacing;
    float half_width = section.hatchParams.y * 0.5;
    float soft = max(fwidth(s) * 0.5, 1e-6);
    float coverage = 1.0 - smoothstep(half_width - soft, half_width + soft, distance);
    return lerp(section.fill, section.hatch, coverage);
}

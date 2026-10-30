#include "common.hlsli"

cbuffer Grid : register(b0, space3) { GridUniforms grid; };

float4 main(float4 position : SV_Position, float2 world : TEXCOORD0) : SV_Target0 {
    float2 center = grid.centerExtentSpacing.xy;
    float extent = grid.centerExtentSpacing.z;
    float spacing = grid.centerExtentSpacing.w;
    float2 minorCoord = world / spacing;
    float2 minorCell = abs(frac(minorCoord - 0.5) - 0.5) / max(fwidth(minorCoord), float2(1e-6, 1e-6));
    float minor = 1.0 - saturate(min(minorCell.x, minorCell.y));
    float2 majorCoord = world / (spacing * 10.0);
    float2 majorCell = abs(frac(majorCoord - 0.5) - 0.5) / max(fwidth(majorCoord), float2(1e-6, 1e-6));
    float major = 1.0 - saturate(min(majorCell.x, majorCell.y));
    float fade = 1.0 - saturate(length(world - center) / (extent * 0.5));
    float alpha = max(minor * 0.35, major * 0.6) * fade;
    float3 color = lerp(grid.minorColor.rgb, grid.majorColor.rgb, major);
    return float4(color * alpha, alpha);
}

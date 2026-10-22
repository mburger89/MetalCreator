#include "common.hlsli"

// The grid is an r32Float texture read at texel centres through a nearest-neighbour sampler, which is a texel fetch, and blended
// here, so no support for filtering a float texture is assumed.
Texture2D<float> grid : register(t0, space2);
SamplerState gridSampler : register(s0, space2);
cbuffer Slice : register(b0, space3) { SliceUniforms slice; };
cbuffer Ramp : register(b1, space3) { FieldRampUniforms ramp; };

float gridValue(int2 texel, float2 size) {
    return grid.SampleLevel(gridSampler, (float2(texel) + 0.5) / size, 0);
}

/// The grid read at `uv` (0...1 over the quad) with a bilinear blend of the four texels round it, texel centres at
/// (i + 0.5) / size, edges held.
float sliceValue(float2 uv) {
    uint width;
    uint height;
    grid.GetDimensions(width, height);
    float2 size = float2(width, height);
    float2 p = uv * size - 0.5;
    float2 f = p - floor(p);
    int2 low = int2(floor(p));
    int2 last = int2(width, height) - 1;
    int2 a = clamp(low, int2(0, 0), last);
    int2 b = clamp(low + 1, int2(0, 0), last);
    float bottom = lerp(gridValue(int2(a.x, a.y), size), gridValue(int2(b.x, a.y), size), f.x);
    float top = lerp(gridValue(int2(a.x, b.y), size), gridValue(int2(b.x, b.y), size), f.x);
    return lerp(bottom, top, f.y);
}

float4 main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0 {
    float3 color = fieldRamp(ramp, sliceValue(uv));
    float alpha = slice.style.x;
    return float4(color * alpha, alpha);
}

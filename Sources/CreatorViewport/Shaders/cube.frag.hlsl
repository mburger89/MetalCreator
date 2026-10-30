#include "common.hlsli"

// The face's name, from the label atlas (r8 coverage, mipmapped), blended in `ink` over the tile's colour (hover and active
// cyan included). uv 0...1 is the text box. Outside it, or with an empty rect, there is no ink. The gradient is taken before
// clamping to the rect, so the mip level stays smooth up to the box's edge.
Texture2D<float> labels : register(t0, space2);
SamplerState atlas : register(s0, space2);
cbuffer Ink : register(b0, space3) { float4 ink; };

struct In {
    float4 position : SV_Position;
    float4 color : TEXCOORD0;
    float2 uv : TEXCOORD1;
    nointerpolation float4 labelRect : TEXCOORD2;
};

float4 main(In input) : SV_Target0 {
    float2 atlasUV = lerp(input.labelRect.xy, input.labelRect.zw, input.uv);
    float2 inRect = clamp(atlasUV, input.labelRect.xy, input.labelRect.zw);
    float coverage = labels.SampleGrad(atlas, inRect, ddx(atlasUV), ddy(atlasUV));
    bool inside = all(input.uv >= 0.0) && all(input.uv <= 1.0) && input.labelRect.z > input.labelRect.x;
    float3 rgb = lerp(input.color.rgb, ink.rgb, inside ? coverage * ink.a : 0.0);
    return float4(rgb * input.color.a, input.color.a);
}

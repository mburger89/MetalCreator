cbuffer Colors : register(b0, space3) {
    float4 top;
    float4 bottom;
};

float4 main(float4 position : SV_Position, float v : TEXCOORD0) : SV_Target0 {
    return float4(lerp(top.rgb, bottom.rgb, saturate(v)), 1.0);
}

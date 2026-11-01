struct In {
    float4 position : SV_Position;
    nointerpolation float4 color : TEXCOORD0;
};

float4 main(In input) : SV_Target0 {
    return float4(input.color.rgb * input.color.a, input.color.a);
}

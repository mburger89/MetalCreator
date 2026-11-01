// The background gradient: one oversized triangle drawn with three vertices, `v` running 0 at the top to 1 at the bottom.
struct Out {
    float4 position : SV_Position;
    float v : TEXCOORD0;
};

Out main(uint vid : SV_VertexID) {
    float2 p = float2(vid == 1u ? 3.0 : -1.0, vid == 2u ? 3.0 : -1.0);
    Out output;
    output.position = float4(p, 0.0, 1.0);
    output.v = (1.0 - p.y) * 0.5;
    return output;
}

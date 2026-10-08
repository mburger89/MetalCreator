/// Per-draw line settings. A positive `widthOverride` replaces every instance's width (the ID pass draws edges
/// 6 points wide). `depthBias` moves lines that many mm toward the camera, so B-rep edges win against their own faces.
struct LineUniforms {
    var widthOverride: Float
    var depthBias: Float
    var padding0: Float
    var padding1: Float
}

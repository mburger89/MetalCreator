#if canImport(Metal)
import Metal

extension ViewportRenderer {
    /// The background gradient, drawn first and ignoring depth.
    func drawBackground(_ palette: ViewportPalette, _ encoder: any MTLRenderCommandEncoder) {
        var colors = BackgroundUniforms(top: palette.backgroundTop, bottom: palette.backgroundBottom)
        encoder.setRenderPipelineState(pipelines.background)
        encoder.setDepthStencilState(pipelines.depthAlways)
        encoder.setFragmentBytes(&colors, length: MemoryLayout<BackgroundUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
#endif

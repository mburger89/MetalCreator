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

    func drawGrid(_ frame: ViewportFrame, _ uniforms: FrameUniforms, _ encoder: any MTLRenderCommandEncoder) {
        var grid = GPUGeometry.gridUniforms(frame)
        encoder.setRenderPipelineState(pipelines.grid)
        encoder.setDepthStencilState(pipelines.depthTest)
        var frameUniforms = uniforms
        encoder.setVertexBytes(&frameUniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setVertexBytes(&grid, length: MemoryLayout<GridUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&grid, length: MemoryLayout<GridUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
#endif

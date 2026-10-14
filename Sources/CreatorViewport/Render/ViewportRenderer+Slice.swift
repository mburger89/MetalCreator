#if canImport(Metal)
import Metal

extension ViewportRenderer {
    /// The field slice (fields spec §6): a translucent quad over the scene, ignoring depth because it passes through the part
    /// (a depth test would hide the half of it that lies inside the solid). It draws nothing for a slice with no valid grid.
    func drawSlice(_ frame: ViewportFrame, _ uniforms: FrameUniforms, _ encoder: any MTLRenderCommandEncoder) {
        guard let slice = frame.slice, slice.isValid, let texture = sliceTextures.texture(for: slice, device: device) else { return }
        var frameUniforms = uniforms
        var geometry = SliceUniforms(slice)
        var ramp = FieldRampUniforms(slice.ramp)
        encoder.setRenderPipelineState(pipelines.slice)
        encoder.setDepthStencilState(pipelines.depthAlways)
        encoder.setVertexBytes(&frameUniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setVertexBytes(&geometry, length: MemoryLayout<SliceUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&geometry, length: MemoryLayout<SliceUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&ramp, length: MemoryLayout<FieldRampUniforms>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
#endif

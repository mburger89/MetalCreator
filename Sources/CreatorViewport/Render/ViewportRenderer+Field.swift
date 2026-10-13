import Metal

extension ViewportRenderer {
    /// Binds what an opaque item's field tint needs (fields spec §6) and returns true: the field pipeline, its value buffer
    /// (one float per de-indexed corner, kept on the mesh until the values change) and the ramp. Returns false, binding
    /// nothing, when the item has no values or ramp, or the values are not one per vertex: the caller draws the plain surface.
    func bindFieldTint(of item: FrameItem, on gpu: GPUMesh, _ encoder: any MTLRenderCommandEncoder) -> Bool {
        guard let values = item.fieldValues, let ramp = item.fieldRamp,
              let buffer = gpu.fieldValues(values, mesh: item.mesh, ramp: ramp, device: device) else { return false }
        var uniforms = FieldRampUniforms(ramp)
        encoder.setRenderPipelineState(pipelines.fieldMesh)
        encoder.setVertexBuffer(buffer, offset: 0, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FieldRampUniforms>.stride, index: 3)
        return true
    }
}

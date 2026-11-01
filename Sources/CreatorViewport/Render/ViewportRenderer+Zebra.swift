#if canImport(Metal)
import Metal

extension ViewportRenderer {
    /// Binds the zebra pipeline and its uniforms (fragment buffer 4; the clip stays at 3) for an opaque item when the frame has a
    /// zebra. A zebra beats a field tint (plan Ruling 3).
    func bindZebra(_ zebra: ViewportZebra?, _ encoder: any MTLRenderCommandEncoder) -> Bool {
        guard let zebra else { return false }
        var uniforms = ZebraUniforms(zebra)
        encoder.setRenderPipelineState(pipelines.zebraMesh)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ZebraUniforms>.stride, index: 4)
        return true
    }
}
#endif

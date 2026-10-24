#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

final class SDLComputePipeline: ComputePipeline {
    let pipeline: SDLGPUComputePipeline
    init(_ pipeline: SDLGPUComputePipeline) { self.pipeline = pipeline }
}
#endif

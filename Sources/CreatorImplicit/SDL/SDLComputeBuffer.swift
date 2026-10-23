#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

final class SDLComputeBuffer: ComputeBuffer {
    let buffer: SDLGPUBuffer
    var length: Int { buffer.size }
    init(_ buffer: SDLGPUBuffer) { self.buffer = buffer }
}
#endif

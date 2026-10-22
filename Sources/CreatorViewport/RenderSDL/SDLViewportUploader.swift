#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// Makes the GPU buffers one frame (or one test) needs and records the copies that fill them into a command buffer. A copy pass
/// cannot run inside a render pass, so everything a pass reads is made before it begins (`SDLFramePlan`).
struct SDLViewportUploader {
    let device: SDLGPUDevice
    let commandBuffer: SDLGPUCommandBuffer

    /// A buffer the vertex stage reads as a storage buffer, holding `values`, or `nil` for an empty array (SDL_GPU refuses
    /// zero-length buffers) or when SDL refuses. The copy that fills it is recorded in `commandBuffer` now; the buffer is
    /// ready for any pass recorded after it.
    func storageBuffer<T>(_ values: [T]) -> SDLGPUBuffer? {
        guard !values.isEmpty else { return nil }
        let size = values.count * MemoryLayout<T>.stride
        return values.withUnsafeBytes { bytes -> SDLGPUBuffer? in
            guard let base = bytes.baseAddress,
                  let buffer = device.makeBuffer(size: size, usage: [.graphicsStorageRead]),
                  let transfer = device.makeTransferBuffer(size: size, direction: .upload),
                  let memory = transfer.map() else { return nil }
            memory.copyMemory(from: base, byteCount: size)
            transfer.unmap()
            commandBuffer.copy(transfer, to: buffer, size: size)
            return buffer
        }
    }
}

/// The bytes of a uniform struct, as a uniform push takes them.
func uniformBytes<T>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value) { Array($0) }
}
#endif

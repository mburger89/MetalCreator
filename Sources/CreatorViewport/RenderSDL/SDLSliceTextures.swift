#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// The field slice's grid as an `r32Float` texture, kept until the slice's generation, size or ramp middle changes, so a redraw of an
/// unchanged slice (an orbit) uploads nothing (`SliceTextures`, the Metal twin; the stored numbers are `SliceTextureValues`'). A nearest
/// sampler reads it at texel centres, so the shader's bilinear blend sees the stored numbers exactly.
final class SDLSliceTextures: @unchecked Sendable {
    private struct Entry {
        let generation: Int
        let columns: Int
        let rows: Int
        let middle: Float
        let texture: SDLGPUTexture
    }

    private let device: SDLGPUDevice
    private var cached: Entry?
    let sampler: SDLGPUSampler?
    /// Textures made so far. Tests use it to tell "kept" from "rebuilt".
    private(set) var uploads = 0

    init(device: SDLGPUDevice) {
        self.device = device
        sampler = device.makeSampler(SDLGPUSamplerDescription(filter: .nearest, mipmapFilter: .nearest))
    }

    /// The texture for `slice`, filled by a copy recorded in the uploader's command buffer (so before the pass that samples it), or
    /// `nil` if SDL refuses it.
    func texture(for slice: ViewportSlice, uploader: SDLViewportUploader) -> SDLGPUTexture? {
        if let cached, cached.generation == slice.generation, cached.columns == slice.columns, cached.rows == slice.rows,
           cached.middle == slice.ramp.midValue {
            return cached.texture
        }
        let texels = SliceTextureValues.texels(of: slice)
        let size = texels.count * MemoryLayout<Float>.stride
        guard let texture = device.makeTexture(SDLGPUTextureDescription(
                  width: slice.columns, height: slice.rows, format: .r32Float, usage: [.sampler])),
              let transfer = device.makeTransferBuffer(size: size, direction: .upload),
              let memory = transfer.map() else { return nil }
        let copied = texels.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            memory.copyMemory(from: base, byteCount: size)
            return true
        }
        transfer.unmap()
        guard copied else { return nil }
        uploader.commandBuffer.copy(transfer, to: texture)
        cached = Entry(generation: slice.generation, columns: slice.columns, rows: slice.rows, middle: slice.ramp.midValue,
                       texture: texture)
        uploads += 1
        return texture
    }
}
#endif

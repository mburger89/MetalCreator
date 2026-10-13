import Metal

/// The field slice's grid as an `r32Float` texture, kept until the slice's generation or size changes, so a redraw of an
/// unchanged slice (an orbit) uploads nothing. A value that is not a number becomes the ramp's middle.
@MainActor
final class SliceTextures {
    private var cached: (generation: Int, columns: Int, rows: Int, texture: any MTLTexture)?
    /// Textures made so far. Tests use it to tell "kept" from "rebuilt".
    private(set) var uploads = 0

    func texture(for slice: ViewportSlice, device: any MTLDevice) -> (any MTLTexture)? {
        if let cached, cached.generation == slice.generation, cached.columns == slice.columns, cached.rows == slice.rows {
            return cached.texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: slice.columns,
                                                                  height: slice.rows, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let values = slice.values.map { $0.isFinite ? $0 : slice.ramp.midValue }
        values.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, slice.columns, slice.rows), mipmapLevel: 0, withBytes: base,
                            bytesPerRow: slice.columns * MemoryLayout<Float>.stride)
        }
        cached = (slice.generation, slice.columns, slice.rows, texture)
        uploads += 1
        return texture
    }
}

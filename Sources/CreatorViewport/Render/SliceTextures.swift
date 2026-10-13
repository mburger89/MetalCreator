import Metal

/// The field slice's grid as an `r32Float` texture, kept until the slice's generation, size or ramp middle changes, so a redraw
/// of an unchanged slice (an orbit) uploads nothing. A NaN becomes the ramp's middle value (which is why the middle is part of
/// the key: a range change without a new generation must refill them), and an infinity is held to the ramp's end it lies beyond.
@MainActor
final class SliceTextures {
    private struct Entry {
        let generation: Int
        let columns: Int
        let rows: Int
        let middle: Float
        let texture: any MTLTexture
    }

    private var cached: Entry?
    /// Textures made so far. Tests use it to tell "kept" from "rebuilt".
    private(set) var uploads = 0

    func texture(for slice: ViewportSlice, device: any MTLDevice) -> (any MTLTexture)? {
        if let cached, cached.generation == slice.generation, cached.columns == slice.columns, cached.rows == slice.rows,
           cached.middle == slice.ramp.midValue {
            return cached.texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: slice.columns,
                                                                  height: slice.rows, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let values = slice.values.map { Self.filled($0, ramp: slice.ramp) }
        values.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, slice.columns, slice.rows), mipmapLevel: 0, withBytes: base,
                            bytesPerRow: slice.columns * MemoryLayout<Float>.stride)
        }
        cached = Entry(generation: slice.generation, columns: slice.columns, rows: slice.rows, middle: slice.ramp.midValue,
                       texture: texture)
        uploads += 1
        return texture
    }

    /// `value` as stored: NaN is the ramp's middle, ±infinity the ramp's high or low end, anything else as it is.
    static func filled(_ value: Float, ramp: FieldRamp) -> Float {
        if value.isNaN { return ramp.midValue }
        if value == .infinity { return ramp.highValue }
        if value == -.infinity { return ramp.lowValue }
        return value
    }
}

import Metal

extension CubeLabelAtlas {
    /// An `r8Unorm` texture with a full mip chain, filled by a blit encoded into `commandBuffer` (before the pass
    /// that samples it): the pixels are copied in through a staging buffer and the smaller levels generated.
    /// `nil` if the device refuses the texture, the buffer or the encoder.
    func makeTexture(device: any MTLDevice, commandBuffer: any MTLCommandBuffer) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height,
                                                                  mipmapped: true)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor),
              let staging = GPUBuffers.make(device, pixels),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: width, sourceBytesPerImage: width * height,
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: texture, destinationSlice: 0,
                  destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        texture.label = "View cube labels"
        return texture
    }
}

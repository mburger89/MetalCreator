#if canImport(MetalUISDLGPU)
import CreatorGeometry
import Foundation
import MetalUISDLGPU

/// The view cube's GPU resources: its tiles, kept until the hover, the camera or the palette changes so a frame of a continuous orbit
/// makes no buffer (spec §7.3's 60 fps), and its face-name texture, made once (the `ViewCubeResources` of the SDL renderer).
final class SDLViewportCube: @unchecked Sendable {
    /// The tiles and what they were built from.
    private struct CachedTiles {
        var hovered: ViewCubeRegion?
        var pose: CameraPose
        var palette: ViewportPalette
        var buffer: SDLGPUBuffer
        var count: Int
    }

    private let device: SDLGPUDevice
    private let atlas: CubeLabelAtlas
    private var tiles: CachedTiles?
    private var labels: SDLGPUTexture?
    /// Linear between texels and between mip levels, clamped at the edge, anisotropic up to 8× (the cube is seen at a slant).
    let sampler: SDLGPUSampler?

    init(device: SDLGPUDevice, atlas: CubeLabelAtlas) {
        self.device = device
        self.atlas = atlas
        sampler = device.makeSampler(SDLGPUSamplerDescription(filter: .linear, mipmapFilter: .linear, maxAnisotropy: 8))
    }

    /// The tiles in `palette`'s colours, rebuilt when the hover, the camera or the palette (the theme) changes.
    func vertices(hovered: ViewCubeRegion?, pose: CameraPose, palette: ViewportPalette,
                  uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        if let tiles, tiles.hovered == hovered, tiles.pose == pose, tiles.palette == palette { return (tiles.buffer, tiles.count) }
        let vertices = GPUGeometry.cubeVertices(hovered: hovered, pose: pose, palette: palette)
        guard let buffer = uploader.storageBuffer(vertices) else { return nil }
        tiles = CachedTiles(hovered: hovered, pose: pose, palette: palette, buffer: buffer, count: vertices.count)
        return (buffer, vertices.count)
    }

    /// The label atlas as an `r8Unorm` texture with a full mip chain, uploaded on first use by copies recorded in the uploader's
    /// command buffer, so call it before the pass that samples it begins. `nil` if SDL refuses the texture or the buffer.
    func labelTexture(uploader: SDLViewportUploader) -> SDLGPUTexture? {
        if let labels { return labels }
        let levels = Int(log2(Double(max(atlas.width, atlas.height)))) + 1
        guard let texture = device.makeTexture(SDLGPUTextureDescription(
                  width: atlas.width, height: atlas.height, format: .r8Unorm, usage: [.sampler, .colorTarget], levelCount: levels)),
              let transfer = device.makeTransferBuffer(size: atlas.pixels.count, direction: .upload),
              let memory = transfer.map() else { return nil }
        let copied = atlas.pixels.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            memory.copyMemory(from: base, byteCount: bytes.count)
            return true
        }
        transfer.unmap()
        guard copied else { return nil }
        uploader.commandBuffer.copy(transfer, to: texture, mipLevel: 0)
        uploader.commandBuffer.generateMipmaps(of: texture)
        labels = texture
        return texture
    }
}
#endif

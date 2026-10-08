import CreatorGeometry
import Metal

/// The view cube's GPU resources: its tiles, kept until the hover or the camera changes so a frame of a continuous
/// orbit allocates no buffers (spec §7.3's 60 fps), and its face-name texture, made once.
@MainActor
final class ViewCubeResources {
    private let device: any MTLDevice
    private var tiles: (hovered: ViewCubeRegion?, pose: CameraPose, buffer: any MTLBuffer, count: Int)?
    private var labels: (any MTLTexture)?
    /// The palette `tiles` were built in.
    private var tilesPalette = ViewportPalette.dracula

    init(device: any MTLDevice) {
        self.device = device
    }

    /// The tiles in `palette`'s colours, rebuilt when the hover, the camera or the palette (the theme) changes.
    func vertices(hovered: ViewCubeRegion?, pose: CameraPose, palette: ViewportPalette) -> (buffer: any MTLBuffer, count: Int)? {
        if let tiles, tiles.hovered == hovered, tiles.pose == pose, tilesPalette == palette { return (tiles.buffer, tiles.count) }
        let vertices = GPUGeometry.cubeVertices(hovered: hovered, pose: pose, palette: palette)
        guard let buffer = GPUBuffers.make(device, vertices) else { return nil }
        tiles = (hovered, pose, buffer, vertices.count)
        tilesPalette = palette
        return (buffer, vertices.count)
    }

    /// The label atlas texture (`CubeLabelAtlas`), rasterized and uploaded on first use by a blit encoded into
    /// `commandBuffer`, so call it before the pass that samples it begins.
    func labelTexture(_ commandBuffer: any MTLCommandBuffer) -> (any MTLTexture)? {
        if let labels { return labels }
        let atlas = CubeLabelAtlas.rasterize() ?? .blank
        labels = atlas.makeTexture(device: device, commandBuffer: commandBuffer)
        return labels
    }
}

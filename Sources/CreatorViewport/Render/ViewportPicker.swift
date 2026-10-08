import Metal

/// Answers "what is under this point?" from the ID pass (spec §6.3). It renders the ID buffer at the view's size
/// in points on its own command queue, because MetalUI's frame buffer may not be waited on (`MV-F` item 5). It
/// reads the buffer back once and reuses it until the camera or the scene changes (`PickKey`).
@MainActor
final class ViewportPicker {
    private let renderer: ViewportRenderer
    private let queue: any MTLCommandQueue
    private var cache: (key: PickKey, width: Int, height: Int, pixels: any MTLBuffer)?
    /// ID passes rendered so far. Tests use it to check the read-back is reused.
    private(set) var renderCount = 0

    init(renderer: ViewportRenderer) throws {
        guard let queue = renderer.device.makeCommandQueue() else {
            throw ViewportRenderError.deviceRefused("a command queue")
        }
        self.renderer = renderer
        self.queue = queue
    }

    /// The face or edge under `point` (viewport points), or `nil` for empty space, a point outside the view, or a
    /// view with no size yet.
    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
        guard !frame.size.isEmpty, point.x.isFinite, point.y.isFinite else { return nil }
        let width = Int(frame.size.width.rounded(.down))
        let height = Int(frame.size.height.rounded(.down))
        guard point.x >= 0, point.y >= 0, point.x < Double(width), point.y < Double(height),
              let pixels = idPixels(for: frame, width: width, height: height) else { return nil }
        let offset = (Int(point.y) * width + Int(point.x)) * MemoryLayout<UInt32>.stride
        return PickID.decode(pixels.contents().load(fromByteOffset: offset, as: UInt32.self))
    }

    private func idPixels(for frame: ViewportFrame, width: Int, height: Int) -> (any MTLBuffer)? {
        let key = frame.pickKey
        if let cache, cache.key == key, cache.width == width, cache.height == height { return cache.pixels }
        let device = renderer.device
        let ids = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ViewportPipelines.idFormat, width: width,
                                                           height: height, mipmapped: false)
        ids.usage = .renderTarget
        ids.storageMode = .private
        let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ViewportPipelines.depthFormat, width: width,
                                                             height: height, mipmapped: false)
        depth.usage = .renderTarget
        depth.storageMode = .private
        let bytesPerRow = width * MemoryLayout<UInt32>.stride
        guard let idTexture = device.makeTexture(descriptor: ids), let depthTexture = device.makeTexture(descriptor: depth),
              let pixels = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer() else { return nil }
        renderer.encodeIDs(frame, into: idTexture, depth: depthTexture, commandBuffer: commandBuffer)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: idTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: pixels, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        renderCount += 1
        guard commandBuffer.status == .completed else { return nil }
        cache = (key, width, height, pixels)
        return pixels
    }
}

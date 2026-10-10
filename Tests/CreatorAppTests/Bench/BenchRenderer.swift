// Test fixture file: draws the app's window and its viewport headless, CPU and GPU, for the §7.3 benchmarks.
import Metal
import MetalUI
import MetalUIText
import simd
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// One window's frame, drawn the way the app draws it but headless: MetalUI builds, lays out and paints the whole
/// window (`renderFrame`, the CPU side), its renderer composites that scene into an offscreen texture, and the
/// viewport's renderer draws the 3D scene into another (the GPU side, each waited for). A real window keeps caches
/// across frames that `renderFrame` starts afresh, and overlaps a frame's GPU work with the next frame's build, so
/// these numbers are an upper bound (docs/verification/performance.md, "Method").
@MainActor
final class BenchRenderer {
    let device: any MTLDevice
    private let interface: Renderer
    private let viewportRenderer: ViewportRenderer
    private let windowTarget: any MTLTexture
    private let viewportTarget: any MTLTexture
    private let atlas = GlyphAtlas(width: 2048, height: 2048)
    private let textSystem = CoreTextTextSystem()

    init() throws {
        device = try #require(MTLCreateSystemDefaultDevice(), "the benchmarks need a Metal device")
        interface = try Renderer(device: device)
        viewportRenderer = try ViewportRenderer(device: device)
        let width = Int(Bench.windowWidth * Bench.scale), height = Int(Bench.windowHeight * Bench.scale)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.pixelFormat, width: width, height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        windowTarget = try #require(device.makeTexture(descriptor: descriptor))
        viewportTarget = try #require(device.makeTexture(descriptor: descriptor))
    }

    /// The viewport main passes drawn so far (`drawViewport(_:)` draws one unless the frame is empty).
    var viewportPasses: Int { viewportRenderer.encodedPasses }

    /// Tells `app`'s viewport the window's size, as its first draw would: the graph panel's placement (and so its
    /// culling) and the viewport's framing need it, and a headless frame never draws the surface.
    func place(_ app: AppModel) {
        app.viewport.recordViewSize(ViewportSize(width: Bench.windowWidth, height: Bench.windowHeight))
    }

    /// The CPU side of a frame: the whole window built, laid out and painted into a scene.
    func windowScene(_ app: AppModel, input: AppInput) -> Scene {
        renderFrame({ ZStack { AppRoot(model: app, input: input) } },
                    size: Size(width: Pixels(Float(Bench.windowWidth)), height: Pixels(Float(Bench.windowHeight))),
                    scaleFactor: Float(Bench.scale), textSystem: textSystem, atlas: atlas)
    }

    /// The window's GPU pass: `scene` composited into the offscreen target, waited for.
    func composite(_ scene: Scene) throws {
        interface.upload(atlas)
        let commandBuffer = try #require(interface.commandQueue.makeCommandBuffer())
        let view = SurfaceView(colorTexture: windowTarget,
                               viewport: MTLViewport(originX: 0, originY: 0, width: Double(windowTarget.width),
                                                     height: Double(windowTarget.height), znear: 0, zfar: 1),
                               projection: matrix_identity_float4x4)
        try interface.encode(scene, view: view, in: commandBuffer)
        Self.commitAndWait(commandBuffer)
    }

    /// The viewport's GPU pass: `viewport`'s current frame drawn into the offscreen target, waited for.
    func drawViewport(_ viewport: ViewportModel) throws {
        let commandBuffer = try #require(interface.commandQueue.makeCommandBuffer())
        viewportRenderer.encode(viewport.frame(at: 0), into: viewportTarget, scale: Bench.scale, commandBuffer: commandBuffer)
        Self.commitAndWait(commandBuffer)
    }

    /// Commits and blocks until the GPU is done. Synchronous on purpose: `waitUntilCompleted` is unavailable in async
    /// code, and `await completed()` would send the non-Sendable buffer off the main actor.
    private static func commitAndWait(_ commandBuffer: any MTLCommandBuffer) {
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

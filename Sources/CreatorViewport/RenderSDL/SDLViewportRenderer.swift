#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import MetalUISDLGPU

/// Draws a `ViewportFrame` with SDL_GPU (cross-platform spec section 4): the Metal `ViewportRenderer`'s passes, in the same
/// order, over the shaders in `Shaders/viewport`.
/// - The main pass draws the background gradient, opaque solids, the ground grid, B-rep edges, ghosts, guides' selected edges,
///   the overlay's fills, lines and points, and handles. It renders into its own 4× MSAA colour and depth targets, resolved into
///   the target it is given (a `GPUSurface`'s, `bgra8Unorm`).
/// - The ID pass (`SDLViewportRenderer+IDPass`) writes `PickID`s into an `r32Uint` target.
/// GPU meshes are cached by mesh serial and dropped once a frame no longer shows them; the buffers that bake colours in are rebuilt
/// when the palette changes. It records into the command buffer it is given and never submits it.
///
/// Threads: it is not main-actor isolated, because a test records into a batch's command buffer on the device's worker thread
/// (`SDLGPUDevice.submitBatch`). It keeps state, so it is used from one thread at a time: the main actor in the app. The ID pass reads
/// none of it while it runs on the worker (`SDLIDPassInputs`).
final class SDLViewportRenderer: @unchecked Sendable {
    /// The handles' line instances and what they were built from.
    struct CachedHandles {
        var handles: [ViewportHandle]
        var scale: Float
        var palette: ViewportPalette
        var buffer: SDLGPUBuffer
        var count: Int
    }

    let device: SDLGPUDevice
    let pipelines: SDLViewportPipelines
    private(set) var meshes: [Int: SDLViewportMesh] = [:]
    private var multisample: (width: Int, height: Int, color: SDLGPUTexture, depth: SDLGPUTexture)?
    /// The handles' instances, kept until the handles, the scale or the palette change, so a frame of a continuous orbit makes no
    /// buffers (spec §7.3's 60 fps).
    var handleBuffer: CachedHandles?
    /// The overlay's instances, kept until what they're built from changes (dashes and the plane grid follow the zoom).
    var overlayBuffer: (key: OverlayBufferKey, buffer: SDLGPUBuffer, count: Int)?
    /// The overlay's fill triangles, kept until the fills or the palette change, and dropped once a frame has none.
    var fillBuffer: (key: FillBufferKey, buffer: SDLGPUBuffer, count: Int)?
    /// Main passes encoded so far. Tests use it to tell "drew" from "bailed out".
    private(set) var encodedPasses = 0

    init(device: SDLGPUDevice, pipelines: SDLViewportPipelines) {
        self.device = device
        self.pipelines = pipelines
    }

    /// With pipelines made from `library`. Making them compiles every shader, which a real GPU does in milliseconds and a CPU driver in
    /// a second, on whichever thread asks: make them once per device.
    convenience init(device: SDLGPUDevice, library: SDLGPUShaderLibrary) throws {
        self.init(device: device, pipelines: try SDLViewportPipelines(device: device, library: library))
    }

    /// The main pass into `target` (`b8g8r8a8Unorm`, `scale` pixels per point). It does nothing for an empty view or a target in
    /// another format. Everything the pass reads is made first, so the copies that fill it come before the pass in `commandBuffer`.
    func encode(_ frame: ViewportFrame, into target: SDLGPUTexture, scale: Double, commandBuffer: SDLGPUCommandBuffer) {
        let width = target.description.width
        let height = target.description.height
        guard width > 0, height > 0, !frame.size.isEmpty, scale.isFinite, scale > 0,
              target.description.format == SDLViewportPipelines.colorFormat,
              let targets = multisampleTargets(width: width, height: height) else { return }
        let uploader = SDLViewportUploader(device: device, commandBuffer: commandBuffer)
        let plan = plan(frame, scale: Float(scale), uploader: uploader)
        let uniforms = GPUGeometry.frameUniforms(frame.pose, size: frame.size, sceneRadius: frame.sceneRadius,
                                                 pixelWidth: width, pixelHeight: height)
        let color = SDLGPUColorAttachment(texture: targets.color, loadOp: .clear, clearColor: (0, 0, 0, 1), storeOp: .resolve,
                                          resolveTexture: target)
        let depth = SDLGPUDepthAttachment(texture: targets.depth, loadOp: .clear, clearDepth: 1, storeOp: .dontCare)
        guard let pass = commandBuffer.beginRenderPass(color: color, depth: depth) else { return }
        record(plan, frame, uniforms, in: pass)
        pass.end()
        encodedPasses += 1
    }

    /// How far (mm) edges move towards the camera so they win against the faces they bound.
    static func edgeDepthBias(_ frame: ViewportFrame) -> Double { max(frame.pose.distance * 0.002, 1e-3) }

    // MARK: - Resources

    private func multisampleTargets(width: Int, height: Int) -> (color: SDLGPUTexture, depth: SDLGPUTexture)? {
        if let multisample, multisample.width == width, multisample.height == height {
            return (multisample.color, multisample.depth)
        }
        guard let color = device.makeTexture(SDLGPUTextureDescription(
                  width: width, height: height, format: SDLViewportPipelines.colorFormat, usage: [.colorTarget],
                  sampleCount: SDLViewportPipelines.sampleCount)),
              let depth = device.makeTexture(SDLGPUTextureDescription(
                  width: width, height: height, format: .d32Float, usage: [.depthStencilTarget],
                  sampleCount: SDLViewportPipelines.sampleCount)) else { return nil }
        multisample = (width, height, color, depth)
        return (color, depth)
    }

    /// Uploads meshes the frame shows for the first time (and the ID pass's edges for each), and drops the ones it no longer shows.
    func prepareMeshes(for frame: ViewportFrame, _ uploader: SDLViewportUploader) {
        let shown = Set(frame.items.map(\.meshSerial))
        meshes = meshes.filter { shown.contains($0.key) }
        for item in frame.items {
            let mesh = meshes[item.meshSerial] ?? SDLViewportMesh(uploader: uploader, mesh: item.mesh)
            meshes[item.meshSerial] = mesh
            if !item.isGuide { _ = mesh.pickEdges(solid: item.solidIndex, uploader: uploader) }
        }
    }
}
#endif

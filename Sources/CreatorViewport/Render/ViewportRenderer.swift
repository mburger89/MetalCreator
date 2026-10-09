import CreatorGeometry
import CreatorKernel
import Metal

/// Draws a `ViewportFrame` with Metal (spec §6.3).
/// - The main pass draws, in order: the background gradient, opaque solids, the ground grid, B-rep edges,
///   ghosts, handles, the view cube (its face names painted on from a label atlas) and the triad. It renders
///   into its own 4× MSAA colour and depth targets, resolved into the MetalView's target.
/// - The ID pass writes `PickID`s into an `r32Uint` target (edges 6 points wide).
/// GPU meshes are cached by mesh serial and dropped once a frame no longer shows them. Every colour comes from the
/// frame's palette (the viewport's theme); the buffers that bake colours in are rebuilt when it changes.
/// It encodes into the buffer it's given and never commits it.
@MainActor
final class ViewportRenderer {
    let device: any MTLDevice
    let pipelines: ViewportPipelines
    private let placeholder: any MTLBuffer
    private var meshes: [Int: GPUMesh] = [:]
    private var multisample: (width: Int, height: Int, color: any MTLTexture, depth: any MTLTexture)?
    /// The handles' instances, kept until the handles change, so a frame of a continuous orbit allocates no
    /// buffers (spec §7.3's 60 fps). The view cube keeps its own.
    var handleBuffer: (handles: [ViewportHandle], scale: Float, buffer: any MTLBuffer, count: Int)?
    /// The overlay's instances, kept until what they're built from changes (dashes and the plane grid follow the zoom).
    var overlayBuffer: (key: OverlayBufferKey, buffer: any MTLBuffer, count: Int)?
    private let cube: ViewCubeResources
    /// The palette `handleBuffer` was built in.
    var handlePalette = ViewportPalette.dracula
    /// Main passes encoded so far. Tests use it to tell "drew" from "bailed out".
    private(set) var encodedPasses = 0

    init(device: any MTLDevice) throws {
        self.device = device
        pipelines = try ViewportPipelines(device: device)
        guard let placeholder = device.makeBuffer(length: 16, options: .storageModeShared) else {
            throw ViewportRenderError.deviceRefused("a placeholder buffer")
        }
        self.placeholder = placeholder
        cube = ViewCubeResources(device: device)
    }

    /// The main pass into `target` (`bgra8Unorm`, `scale` pixels per point). It does nothing for an empty view or
    /// a target in another format.
    func encode(_ frame: ViewportFrame, into target: any MTLTexture, scale: Double, commandBuffer: any MTLCommandBuffer) {
        let width = target.width
        let height = target.height
        guard width > 0, height > 0, !frame.size.isEmpty, scale.isFinite, scale > 0,
              target.pixelFormat == ViewportPipelines.colorFormat,
              let targets = multisampleTargets(width: width, height: height) else { return }
        prepareMeshes(for: frame)
        let labels = cube.labelTexture(commandBuffer)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.color
        pass.colorAttachments[0].resolveTexture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.depthAttachment.texture = targets.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let pixelScale = Float(scale)
        let uniforms = GPUGeometry.frameUniforms(frame.pose, size: frame.size, sceneRadius: frame.sceneRadius,
                                                 pixelWidth: width, pixelHeight: height)
        drawBackground(frame.palette, encoder)
        drawSolids(frame, ghosts: false, uniforms, encoder)
        if frame.overlay.gridPlane == nil { drawGrid(frame, uniforms, encoder) }
        drawEdges(frame, uniforms, scale: pixelScale, encoder)
        drawSolids(frame, ghosts: true, uniforms, encoder)
        drawOverlay(frame, uniforms, scale: pixelScale, encoder)
        if let handles = handleInstances(for: frame, scale: pixelScale) {
            drawLines(handles.buffer, count: handles.count, uniforms, depth: pipelines.depthAlways, style: Self.plainLines,
                      encoder)
        }
        if let labels, frame.showsViewCube { drawCube(frame, labels: labels, scale: scale, width: width, height: height, encoder) }
        drawTriad(frame, scale: scale, width: width, height: height, encoder)
        encoder.endEncoding()
        encodedPasses += 1
    }

    /// The ID pass into `ids` (`r32Uint`, one texel per point) with a matching single-sample `depth` target.
    /// Faces write their face pick IDs and edges theirs, 6 points wide and biased towards the camera.
    func encodeIDs(_ frame: ViewportFrame, into ids: any MTLTexture, depth: any MTLTexture, commandBuffer: any MTLCommandBuffer) {
        prepareMeshes(for: frame)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = ids
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let uniforms = GPUGeometry.frameUniforms(frame.pose, size: frame.size, sceneRadius: frame.sceneRadius,
                                                 pixelWidth: ids.width, pixelHeight: ids.height)
        encoder.setRenderPipelineState(pipelines.idMesh)
        encoder.setDepthStencilState(pipelines.depthWrite)
        bind(uniforms, encoder)
        for item in frame.items {
            guard let gpu = meshes[item.meshSerial], let vertices = gpu.vertexBuffer,
                  let base = PickID.base(kind: PickID.faceKind, solid: item.solidIndex) else { continue }
            var draw = DrawUniforms(pickBase: base, ghost: 0, faceCount: UInt32(gpu.faceCount), padding: 0)
            encoder.setVertexBuffer(vertices, offset: 0, index: 0)
            encoder.setFragmentBytes(&draw, length: MemoryLayout<DrawUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gpu.vertexCount)
        }
        let style = LineUniforms(widthOverride: 6, depthBias: Float(edgeDepthBias(frame)), padding0: 0, padding1: 0)
        for item in frame.items {
            let key = EdgeInstanceKey(solid: item.solidIndex, selected: [], selectedOnly: false, scale: 1)
            guard let edges = meshes[item.meshSerial]?.edges(key, palette: frame.palette, device: device) else { continue }
            drawLines(edges.buffer, count: edges.count, uniforms, depth: pipelines.depthTest, style: style,
                      pipeline: pipelines.idLine, encoder)
        }
        encoder.endEncoding()
    }

    // MARK: - Layers

    static let plainLines = LineUniforms(widthOverride: 0, depthBias: 0, padding0: 0, padding1: 0)

    /// How far (mm) edges move towards the camera so they win against the faces they bound.
    private func edgeDepthBias(_ frame: ViewportFrame) -> Double { max(frame.pose.distance * 0.002, 1e-3) }

    private func bind(_ uniforms: FrameUniforms, _ encoder: any MTLRenderCommandEncoder) {
        var copy = uniforms
        encoder.setVertexBytes(&copy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
    }

    private func drawBackground(_ palette: ViewportPalette, _ encoder: any MTLRenderCommandEncoder) {
        var colors = BackgroundUniforms(top: palette.backgroundTop, bottom: palette.backgroundBottom)
        encoder.setRenderPipelineState(pipelines.background)
        encoder.setDepthStencilState(pipelines.depthAlways)
        encoder.setFragmentBytes(&colors, length: MemoryLayout<BackgroundUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// Opaque solids, or ghosts. Ghosts take two steps so each pixel blends once, at its nearest ghost surface
    /// (spec §6.3's 40%, with no back faces or interior showing through): a depth-only prepass, then the blended
    /// colour pass, which passes only where its depth equals the prepass's (`lessEqual`, no write).
    private func drawSolids(_ frame: ViewportFrame, ghosts: Bool, _ uniforms: FrameUniforms,
                            _ encoder: any MTLRenderCommandEncoder) {
        let items = frame.items.filter { $0.isGhost == ghosts }
        guard !items.isEmpty else { return }
        bind(uniforms, encoder)
        var shade = ShadeUniforms(frame.palette)
        encoder.setFragmentBytes(&shade, length: MemoryLayout<ShadeUniforms>.stride, index: 2)
        if ghosts {
            encoder.setRenderPipelineState(pipelines.ghostDepth)
            encoder.setDepthStencilState(pipelines.depthWrite)
            drawMeshes(items, ghost: true, encoder)
        }
        encoder.setRenderPipelineState(ghosts ? pipelines.ghost : pipelines.mesh)
        encoder.setDepthStencilState(ghosts ? pipelines.depthTest : pipelines.depthWrite)
        drawMeshes(items, ghost: ghosts, encoder)
    }

    private func drawMeshes(_ items: [FrameItem], ghost: Bool, _ encoder: any MTLRenderCommandEncoder) {
        for item in items {
            guard let gpu = meshes[item.meshSerial], let vertices = gpu.vertexBuffer else { continue }
            var draw = DrawUniforms(pickBase: 0, ghost: ghost ? 1 : 0, faceCount: UInt32(gpu.faceCount), padding: 0)
            encoder.setVertexBuffer(vertices, offset: 0, index: 0)
            encoder.setFragmentBytes(&draw, length: MemoryLayout<DrawUniforms>.stride, index: 0)
            bindFaceFlags(gpu, item, encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gpu.vertexCount)
        }
    }

    /// `setFragmentBytes` takes at most 4 KB.
    private static let inlineBytesLimit = 4096

    /// Face flags go inline while they fit (up to 1024 faces), else in a buffer the mesh keeps until the hover or
    /// selection changes. Either way a frame allocates no buffer for them.
    private func bindFaceFlags(_ gpu: GPUMesh, _ item: FrameItem, _ encoder: any MTLRenderCommandEncoder) {
        let length = gpu.faceCount * MemoryLayout<UInt32>.stride
        if length > 0, length <= Self.inlineBytesLimit {
            let flags = GPUGeometry.faceFlags(count: gpu.faceCount, hovered: item.hoveredFace, selected: item.selectedFaces)
            flags.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { encoder.setFragmentBytes(base, length: bytes.count, index: 1) }
            }
        } else {
            let buffer = gpu.faceFlags(hovered: item.hoveredFace, selected: item.selectedFaces, device: device)
            encoder.setFragmentBuffer(buffer ?? placeholder, offset: 0, index: 1)
        }
    }

    private func drawGrid(_ frame: ViewportFrame, _ uniforms: FrameUniforms, _ encoder: any MTLRenderCommandEncoder) {
        var grid = GPUGeometry.gridUniforms(frame)
        encoder.setRenderPipelineState(pipelines.grid)
        encoder.setDepthStencilState(pipelines.depthTest)
        bind(uniforms, encoder)
        encoder.setVertexBytes(&grid, length: MemoryLayout<GridUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&grid, length: MemoryLayout<GridUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// B-rep edges of opaque solids. "Shaded" mode still shows the edges a rule selected.
    private func drawEdges(_ frame: ViewportFrame, _ uniforms: FrameUniforms, scale: Float,
                           _ encoder: any MTLRenderCommandEncoder) {
        let style = LineUniforms(widthOverride: 0, depthBias: Float(edgeDepthBias(frame)), padding0: 0, padding1: 0)
        let selectedOnly = frame.shading == .shaded
        for item in frame.items where !item.isGhost && (!selectedOnly || !item.selectedEdges.isEmpty) {
            let key = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: selectedOnly,
                                      scale: scale)
            guard let edges = meshes[item.meshSerial]?.edges(key, palette: frame.palette, device: device) else { continue }
            drawLines(edges.buffer, count: edges.count, uniforms, depth: pipelines.depthTest, style: style, encoder)
        }
    }

    func drawLines(_ buffer: any MTLBuffer, count: Int, _ uniforms: FrameUniforms,
                   depth: any MTLDepthStencilState, style: LineUniforms,
                   pipeline: (any MTLRenderPipelineState)? = nil, _ encoder: any MTLRenderCommandEncoder) {
        guard count > 0 else { return }
        var style = style
        encoder.setRenderPipelineState(pipeline ?? pipelines.line)
        encoder.setDepthStencilState(depth)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        bind(uniforms, encoder)
        encoder.setVertexBytes(&style, length: MemoryLayout<LineUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
    }

    /// The view cube in its own viewport at the top-left, its face names painted on from `labels`. A cube is
    /// convex, so back-face culling replaces a depth test, and a face turned away hides its name with it.
    private func drawCube(_ frame: ViewportFrame, labels: any MTLTexture, scale: Double, width: Int, height: Int,
                          _ encoder: any MTLRenderCommandEncoder) {
        let layout = frame.cube
        let x = layout.origin.x * scale
        let y = layout.origin.y * scale
        let side = layout.side * scale
        guard x >= 0, y >= 0, x + side <= Double(width), y + side <= Double(height),
              let tiles = cube.vertices(hovered: frame.hoveredCubeRegion, pose: frame.pose, palette: frame.palette) else { return }
        encoder.setViewport(MTLViewport(originX: x, originY: y, width: side, height: side, znear: 0, zfar: 1))
        let uniforms = GPUGeometry.frameUniforms(layout.widgetPose(frame.pose), size: layout.widgetSize, sceneRadius: 2,
                                                 pixelWidth: Int(side), pixelHeight: Int(side))
        encoder.setRenderPipelineState(pipelines.cube)
        encoder.setDepthStencilState(pipelines.depthAlways)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        encoder.setVertexBuffer(tiles.buffer, offset: 0, index: 0)
        bind(uniforms, encoder)
        var ink = frame.palette.cubeLabel
        encoder.setFragmentBytes(&ink, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentTexture(labels, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tiles.count)
        encoder.setCullMode(.none)
    }

    /// The axis triad in its own viewport at the bottom-left.
    private func drawTriad(_ frame: ViewportFrame, scale: Double, width: Int, height: Int,
                           _ encoder: any MTLRenderCommandEncoder) {
        let triad = frame.triad
        let origin = triad.origin(in: frame.size)
        let x = origin.x * scale
        let y = origin.y * scale
        let side = triad.side * scale
        let instances = GPUGeometry.triadInstances(scale: Float(scale), palette: frame.palette)
        guard x >= 0, y >= 0, x + side <= Double(width), y + side <= Double(height),
              let buffer = GPUBuffers.make(device, instances) else { return }
        encoder.setViewport(MTLViewport(originX: x, originY: y, width: side, height: side, znear: 0, zfar: 1))
        let uniforms = GPUGeometry.frameUniforms(triad.widgetPose(frame.pose),
                                                 size: ViewportSize(width: triad.side, height: triad.side), sceneRadius: 2,
                                                 pixelWidth: Int(side), pixelHeight: Int(side))
        drawLines(buffer, count: instances.count, uniforms, depth: pipelines.depthAlways, style: Self.plainLines, encoder)
    }

    // MARK: - Resources

    private func multisampleTargets(width: Int, height: Int) -> (color: any MTLTexture, depth: any MTLTexture)? {
        if let multisample, multisample.width == width, multisample.height == height {
            return (multisample.color, multisample.depth)
        }
        func texture(_ format: MTLPixelFormat) -> (any MTLTexture)? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height,
                                                                      mipmapped: false)
            descriptor.textureType = .type2DMultisample
            descriptor.sampleCount = ViewportPipelines.sampleCount
            descriptor.usage = .renderTarget
            descriptor.storageMode = .private
            return device.makeTexture(descriptor: descriptor)
        }
        guard let color = texture(ViewportPipelines.colorFormat), let depth = texture(ViewportPipelines.depthFormat) else {
            return nil
        }
        multisample = (width, height, color, depth)
        return (color, depth)
    }

    /// Uploads meshes the frame shows for the first time and drops the ones it no longer shows.
    private func prepareMeshes(for frame: ViewportFrame) {
        let shown = Set(frame.items.map(\.meshSerial))
        meshes = meshes.filter { shown.contains($0.key) }
        for item in frame.items where meshes[item.meshSerial] == nil {
            meshes[item.meshSerial] = GPUMesh(device: device, mesh: item.mesh)
        }
    }
}

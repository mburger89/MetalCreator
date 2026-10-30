#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// What the ID pass draws, gathered on the main actor so the batch that records it, on the device's worker thread, reads none of the
/// renderer's state: the pipelines and buffers are immutable once made, and the batch retains them until its fence signals.
struct SDLIDPassInputs: @unchecked Sendable {
    struct Solid {
        var vertices: SDLGPUBuffer
        var vertexCount: Int
        /// `PickID.base` for the solid's faces.
        var pickBase: UInt32
    }

    var pipelines: SDLViewportPipelines
    var solids: [Solid]
    var edges: [(buffer: SDLGPUBuffer, count: Int)]
    /// The section's caps: drawn after the faces writing 0 with depth, so a click on a cap picks nothing.
    var caps: [(buffer: SDLGPUBuffer, count: Int, uniforms: SectionUniforms)]
    var uniforms: FrameUniforms
    var clip: ClipUniforms
    /// `SDLViewportRenderer.edgeDepthBias`: edges move this far (mm) towards the camera.
    var edgeBias: Float

    /// Whether anything is drawn (an empty scene has no ID pass to run).
    var isEmpty: Bool { solids.isEmpty && edges.isEmpty && caps.isEmpty }
}

extension SDLViewportRenderer {
    /// The ID pass's draws for `frame` at the size of the ID target, or `nil` if a mesh the frame shows has not been prepared yet (a
    /// draw prepares them: `encode`). Guides are no part of the scene: they're never in the ID pass.
    func idPassInputs(for frame: ViewportFrame, width: Int, height: Int) -> SDLIDPassInputs? {
        var solids: [SDLIDPassInputs.Solid] = []
        var edges: [(buffer: SDLGPUBuffer, count: Int)] = []
        for item in frame.items where !item.isGuide {
            guard let mesh = meshes[item.meshSerial], mesh.hasPickEdges(solid: item.solidIndex) else { return nil }
            if let vertices = mesh.vertexBuffer, let base = PickID.base(kind: PickID.faceKind, solid: item.solidIndex) {
                solids.append(SDLIDPassInputs.Solid(vertices: vertices, vertexCount: mesh.vertexCount, pickBase: base))
            }
            if let instances = mesh.cachedPickEdges(solid: item.solidIndex) { edges.append(instances) }
        }
        var caps: [(buffer: SDLGPUBuffer, count: Int, uniforms: SectionUniforms)] = []
        if let section = frame.section {
            // Like a mesh, a section a draw has not prepared yet is not drawn here (the draw that follows prepares it).
            guard let buffers = sectionBuffers, buffers.key.generation == section.generation,
                  buffers.key.palette == frame.palette else { return nil }
            for cap in buffers.caps {
                let draw = SectionUniforms(section, angle: cap.angle, frame: frame, depthBias: Self.capDepthBias(frame))
                caps.append((cap.buffer, cap.count, draw))
            }
        }
        let uniforms = GPUGeometry.frameUniforms(frame.pose, size: frame.size, sceneRadius: frame.sceneRadius,
                                                 pixelWidth: width, pixelHeight: height)
        return SDLIDPassInputs(pipelines: pipelines, solids: solids, edges: edges, caps: caps, uniforms: uniforms,
                               clip: ClipUniforms(frame.clip),
                               edgeBias: Float(Self.edgeDepthBias(frame)))
    }

    /// The ID pass into `ids` (`r32Uint`, one texel per point) with a matching single-sample `depth` target. Faces write their face
    /// pick IDs and edges theirs, 6 points wide and biased towards the camera. It is static: it touches nothing but `inputs`.
    static func encodeIDs(_ inputs: SDLIDPassInputs, into ids: SDLGPUTexture, depth: SDLGPUTexture,
                          commandBuffer: SDLGPUCommandBuffer) {
        let color = SDLGPUColorAttachment(texture: ids, loadOp: .clear, clearColor: (0, 0, 0, 0), storeOp: .store)
        let depthTarget = SDLGPUDepthAttachment(texture: depth, loadOp: .clear, clearDepth: 1, storeOp: .dontCare)
        guard let pass = commandBuffer.beginRenderPass(color: color, depth: depthTarget) else { return }
        let camera = uniformBytes(inputs.uniforms)
        let clip = uniformBytes(inputs.clip)
        for solid in inputs.solids {
            pass.bind(inputs.pipelines.idMesh)
            pass.pushVertexUniform(camera, at: 0)
            pass.pushVertexUniform(uniformBytes(DrawUniforms(pickBase: solid.pickBase, ghost: 0, faceCount: 0, padding: 0)), at: 1)
            pass.pushFragmentUniform(clip, at: 0)
            pass.bindVertexStorageBuffers([solid.vertices])
            pass.draw(vertexCount: solid.vertexCount)
        }
        for cap in inputs.caps {
            pass.bind(inputs.pipelines.idSection)
            pass.pushVertexUniform(camera, at: 0)
            pass.pushVertexUniform(uniformBytes(cap.uniforms), at: 1)
            pass.pushFragmentUniform(clip, at: 0)
            pass.bindVertexStorageBuffers([cap.buffer])
            pass.draw(vertexCount: cap.count)
        }
        let style = LineUniforms(widthOverride: 6, depthBias: inputs.edgeBias, padding0: 0, padding1: 0)
        for edges in inputs.edges where edges.count > 0 {
            pass.bind(inputs.pipelines.idLine)
            pass.pushVertexUniform(camera, at: 0)
            pass.pushVertexUniform(uniformBytes(style), at: 1)
            pass.pushFragmentUniform(clip, at: 0)
            pass.bindVertexStorageBuffers([edges.buffer])
            pass.draw(vertexCount: 4, instanceCount: edges.count)
        }
        pass.end()
    }
}
#endif

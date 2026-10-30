#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// A render pass that pushes the frame's camera (vertex uniform slot 0 of every pipeline that reads it) each time it binds a
/// pipeline, so no draw depends on what an earlier pipeline left in the slot.
struct SDLPassRecorder {
    let pass: SDLGPURenderPass
    let camera: [UInt8]

    func bind(_ pipeline: SDLGPUGraphicsPipeline) {
        pass.bind(pipeline)
        pass.pushVertexUniform(camera, at: 0)
    }
}

extension SDLViewportRenderer {
    /// Records the main pass from `plan`, in the Metal renderer's order: the background gradient, opaque solids, the section's caps, the ground grid
    /// (unless the overlay has a plane grid of its own), B-rep edges, the cap outlines, ghosts, guides, the field slice, the overlay's fills, lines and points, handles, the
    /// view cube and the triad (each in a square of its own).
    func record(_ plan: SDLFramePlan, _ frame: ViewportFrame, _ uniforms: FrameUniforms, in pass: SDLGPURenderPass) {
        let recorder = SDLPassRecorder(pass: pass, camera: uniformBytes(uniforms))
        drawBackground(frame.palette, in: pass)
        let shade = ShadeUniforms(frame.palette)
        let clip = ClipUniforms(frame.clip)
        drawSolids(plan.opaque, ghosts: false, shade: shade, clip: clip, in: recorder)
        drawCaps(plan.caps, clip: clip, in: recorder)
        if frame.overlay.gridPlane == nil { drawGrid(frame, in: recorder) }
        for edges in plan.edges { drawLines(edges, pipeline: pipelines.lineTest, in: recorder) }
        if let outlines = plan.outlines { drawLines(outlines, pipeline: pipelines.lineTest, in: recorder) }
        drawSolids(plan.ghosts, ghosts: true, shade: shade, clip: clip, in: recorder)
        for guide in plan.guides { drawLines(guide, pipeline: pipelines.lineTest, in: recorder) }
        for faded in plan.hiddenGuides { drawLines(faded, pipeline: pipelines.lineBehind, in: recorder) }
        drawOverlays(plan, in: recorder)
        if let cube = plan.cube { drawCube(cube, in: pass) }
        if let triad = plan.triad { drawTriad(triad, in: pass) }
    }

    /// The field slice, the overlay's fills, lines and points, and the handles.
    private func drawOverlays(_ plan: SDLFramePlan, in recorder: SDLPassRecorder) {
        if let slice = plan.slice { drawSlice(slice, in: recorder) }
        if let fills = plan.fills { drawFills(fills, in: recorder) }
        if let overlay = plan.overlay { drawLines(overlay, pipeline: pipelines.lineAlways, in: recorder) }
        if let handles = plan.handles { drawLines(handles, pipeline: pipelines.lineAlways, in: recorder) }
    }

    /// The background gradient, drawn first and ignoring depth.
    private func drawBackground(_ palette: ViewportPalette, in pass: SDLGPURenderPass) {
        let colors = BackgroundUniforms(top: palette.backgroundTop, bottom: palette.backgroundBottom)
        pass.bind(pipelines.background)
        pass.pushFragmentUniform(uniformBytes(colors), at: 0)
        pass.draw(vertexCount: 3)
    }

    /// Opaque solids, or ghosts (blended, tested against the prepass's depth). A solid with a tint draws with the field pipeline.
    private func drawSolids(_ solids: [SDLFramePlan.Solid], ghosts: Bool, shade: ShadeUniforms, clip: ClipUniforms,
                            in recorder: SDLPassRecorder) {
        if ghosts {
            // The prepass: the nearest ghost surface's depth, with no colour.
            for solid in solids {
                drawSolid(solid, plain: pipelines.ghostDepth, ghosts: true, shade: shade, clip: clip, in: recorder)
            }
        }
        for solid in solids {
            drawSolid(solid, plain: ghosts ? pipelines.ghost : pipelines.mesh, ghosts: ghosts, shade: shade, clip: clip, in: recorder)
        }
    }

    /// One solid with `plain`, or with the field pipeline when it has a tint (a ghost never does).
    private func drawSolid(_ solid: SDLFramePlan.Solid, plain: SDLGPUGraphicsPipeline, ghosts: Bool, shade: ShadeUniforms,
                           clip: ClipUniforms, in recorder: SDLPassRecorder) {
        let pass = recorder.pass
        let draw = DrawUniforms(pickBase: 0, ghost: ghosts ? 1 : 0, faceCount: UInt32(solid.faceCount), padding: 0)
        if let tint = solid.tint {
            recorder.bind(pipelines.fieldMesh)
            pass.pushFragmentUniform(uniformBytes(shade), at: 0)
            pass.pushFragmentUniform(uniformBytes(tint.ramp), at: 1)
            pass.pushFragmentUniform(uniformBytes(clip), at: 2)
            pass.bindVertexStorageBuffers([solid.vertices, solid.flags, tint.values])
        } else {
            recorder.bind(plain)
            pass.pushFragmentUniform(uniformBytes(draw), at: 0)
            pass.pushFragmentUniform(uniformBytes(shade), at: 1)
            pass.pushFragmentUniform(uniformBytes(clip), at: 2)
            pass.bindVertexStorageBuffers([solid.vertices, solid.flags])
        }
        pass.pushVertexUniform(uniformBytes(draw), at: 1)
        pass.draw(vertexCount: solid.vertexCount)
    }

    private func drawGrid(_ frame: ViewportFrame, in recorder: SDLPassRecorder) {
        let grid = uniformBytes(GPUGeometry.gridUniforms(frame))
        recorder.bind(pipelines.grid)
        recorder.pass.pushVertexUniform(grid, at: 1)
        recorder.pass.pushFragmentUniform(grid, at: 0)
        recorder.pass.draw(vertexCount: 4)
    }

    /// Instanced line quads, four vertices as a strip per instance.
    func drawLines(_ lines: SDLFramePlan.Lines, pipeline: SDLGPUGraphicsPipeline, in recorder: SDLPassRecorder) {
        guard lines.count > 0 else { return }
        recorder.bind(pipeline)
        recorder.pass.bindVertexStorageBuffers([lines.buffer])
        recorder.pass.pushVertexUniform(uniformBytes(lines.style), at: 1)
        recorder.pass.pushFragmentUniform(uniformBytes(lines.clip), at: 0)
        recorder.pass.draw(vertexCount: 4, instanceCount: lines.count)
    }

    private func drawSlice(_ slice: SDLFramePlan.Slice, in recorder: SDLPassRecorder) {
        recorder.bind(pipelines.slice)
        recorder.pass.pushVertexUniform(uniformBytes(slice.geometry), at: 1)
        recorder.pass.pushFragmentUniform(uniformBytes(slice.geometry), at: 0)
        recorder.pass.pushFragmentUniform(uniformBytes(slice.ramp), at: 1)
        recorder.pass.bindFragmentSamplers([(texture: slice.texture, sampler: slice.sampler)])
        recorder.pass.draw(vertexCount: 4)
    }

    private func drawFills(_ fills: (buffer: SDLGPUBuffer, count: Int), in recorder: SDLPassRecorder) {
        recorder.bind(pipelines.fill)
        recorder.pass.bindVertexStorageBuffers([fills.buffer])
        recorder.pass.draw(vertexCount: fills.count)
    }
}
#endif

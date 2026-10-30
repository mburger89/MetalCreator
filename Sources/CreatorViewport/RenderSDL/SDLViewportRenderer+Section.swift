#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// The GPU copy of a `ViewportSection` (the Metal side's `SectionBuffers`): one vertex storage buffer per cap and the outlines' line
/// instances, kept until the section's generation or the palette changes, and dropped once a frame has no section.
struct SDLSectionBuffers {
    struct Key: Hashable {
        var generation: Int
        var palette: ViewportPalette
    }

    struct CapBuffer {
        var buffer: SDLGPUBuffer
        var count: Int
        var angle: Double
    }

    var key: Key
    var caps: [CapBuffer]
    var lines: (buffer: SDLGPUBuffer, count: Int)?
}

extension SDLViewportRenderer {
    /// How far (mm) a cap moves towards the eye: half the edges' bias.
    static func capDepthBias(_ frame: ViewportFrame) -> Float { Float(edgeDepthBias(frame) * 0.5) }

    /// Makes (or keeps) the section's buffers; the ID pass and the main pass both read `sectionBuffers`.
    func prepareSection(for frame: ViewportFrame, _ uploader: SDLViewportUploader) {
        guard let section = frame.section else {
            sectionBuffers = nil
            return
        }
        let key = SDLSectionBuffers.Key(generation: section.generation, palette: frame.palette)
        if let cached = sectionBuffers, cached.key == key { return }
        var caps: [SDLSectionBuffers.CapBuffer] = []
        for cap in section.caps {
            let vertices = SectionVertex.vertices(of: cap)
            if let buffer = uploader.storageBuffer(vertices) {
                caps.append(SDLSectionBuffers.CapBuffer(buffer: buffer, count: vertices.count, angle: cap.hatchAngle))
            }
        }
        // The width rides in the style's override, so the instances carry 1.
        let instances = GPUGeometry.sectionOutlineInstances(section, width: 1, palette: frame.palette)
        let lines = uploader.storageBuffer(instances).map { (buffer: $0, count: instances.count) }
        sectionBuffers = SDLSectionBuffers(key: key, caps: caps, lines: lines)
    }

    /// The caps and outlines of `frame` for the main pass. The outlines are clipped by the current clip with its plane moved by the
    /// edge bias (they move that far towards the eye): an outline on the plane stays, one on the cut-away side (an old section) goes.
    func planSection(_ frame: ViewportFrame, scale: Float, into plan: inout SDLFramePlan) {
        guard let section = frame.section, let buffers = sectionBuffers else { return }
        for cap in buffers.caps {
            let uniforms = SectionUniforms(section, angle: cap.angle, frame: frame, depthBias: Self.capDepthBias(frame))
            plan.caps.append(SDLFramePlan.Cap(vertices: cap.buffer, count: cap.count, uniforms: uniforms))
        }
        if let lines = buffers.lines {
            let bias = Float(Self.edgeDepthBias(frame))
            var clip = ClipUniforms(frame.clip)
            if clip.enabled != 0 { clip.plane.w -= bias }
            let style = LineUniforms(widthOverride: GPUGeometry.edgeWidth * scale, depthBias: bias, padding0: 0, padding1: 0)
            plan.outlines = SDLFramePlan.Lines(buffer: lines.buffer, count: lines.count, style: style, clip: clip)
        }
    }

    /// The caps, one draw each, with depth write.
    func drawCaps(_ caps: [SDLFramePlan.Cap], clip: ClipUniforms, in recorder: SDLPassRecorder) {
        for cap in caps {
            recorder.bind(pipelines.section)
            recorder.pass.bindVertexStorageBuffers([cap.vertices])
            recorder.pass.pushVertexUniform(uniformBytes(cap.uniforms), at: 1)
            recorder.pass.pushFragmentUniform(uniformBytes(cap.uniforms), at: 0)
            recorder.pass.pushFragmentUniform(uniformBytes(clip), at: 1)
            recorder.pass.draw(vertexCount: cap.count)
        }
    }
}
#endif

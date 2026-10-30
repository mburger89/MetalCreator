#if canImport(Metal)
import CreatorGeometry
import Metal

/// The GPU copy of a `ViewportSection`: one vertex buffer per cap and the outlines' line instances, kept until the section's
/// generation or the palette changes, and dropped once a frame has no section.
struct SectionBuffers {
    struct Key: Hashable {
        var generation: Int
        var palette: ViewportPalette
    }

    struct CapBuffer {
        var buffer: any MTLBuffer
        var count: Int
        var angle: Double
    }

    var key: Key
    var caps: [CapBuffer]
    var lines: (buffer: any MTLBuffer, count: Int)?
}

extension ViewportRenderer {
    /// How far (mm) a cap moves towards the eye: half the edges' bias.
    func capDepthBias(_ frame: ViewportFrame) -> Float { Float(edgeDepthBias(frame) * 0.5) }

    func sectionBuffers(for frame: ViewportFrame) -> SectionBuffers? {
        guard let section = frame.section else {
            sectionCache = nil
            return nil
        }
        let key = SectionBuffers.Key(generation: section.generation, palette: frame.palette)
        if let cached = sectionCache, cached.key == key { return cached }
        var caps: [SectionBuffers.CapBuffer] = []
        for cap in section.caps {
            let vertices = SectionVertex.vertices(of: cap)
            if let buffer = GPUBuffers.make(device, vertices) {
                caps.append(SectionBuffers.CapBuffer(buffer: buffer, count: vertices.count, angle: cap.hatchAngle))
            }
        }
        // The width rides in the style's override, so the instances carry 1.
        let instances = GPUGeometry.sectionOutlineInstances(section, width: 1, palette: frame.palette)
        let lines = GPUBuffers.make(device, instances).map { (buffer: $0, count: instances.count) }
        let built = SectionBuffers(key: key, caps: caps, lines: lines)
        sectionCache = built
        return built
    }

    /// The caps, one draw each, with depth write: they hide what lies behind them, and the clip (the current one, even when a
    /// cap is older than the plane) discards what lies on the cut-away side.
    func drawCaps(_ frame: ViewportFrame, _ uniforms: FrameUniforms, ids: Bool = false,
                  _ encoder: any MTLRenderCommandEncoder) {
        guard let section = frame.section, let buffers = sectionBuffers(for: frame) else { return }
        var frameUniforms = uniforms
        var clip = ClipUniforms(frame.clip)
        encoder.setRenderPipelineState(ids ? pipelines.idSection : pipelines.section)
        encoder.setDepthStencilState(pipelines.depthWrite)
        encoder.setCullMode(.none)
        encoder.setVertexBytes(&frameUniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&clip, length: MemoryLayout<ClipUniforms>.stride, index: 1)
        for cap in buffers.caps {
            var draw = SectionUniforms(section, angle: cap.angle, frame: frame, depthBias: capDepthBias(frame))
            encoder.setVertexBuffer(cap.buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&draw, length: MemoryLayout<SectionUniforms>.stride, index: 2)
            encoder.setFragmentBytes(&draw, length: MemoryLayout<SectionUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cap.count)
        }
    }

    /// The cap outlines through the line pipeline, tested against the depth and clipped by the current clip (ruling 6), so an old
    /// cap's outline beyond a new plane is discarded.
    func drawSectionOutlines(_ frame: ViewportFrame, _ uniforms: FrameUniforms, scale: Float,
                             _ encoder: any MTLRenderCommandEncoder) {
        guard let lines = sectionBuffers(for: frame)?.lines else { return }
        let style = LineUniforms(widthOverride: GPUGeometry.edgeWidth * scale, depthBias: Float(edgeDepthBias(frame)),
                                 padding0: 0, padding1: 0)
        // The lines move towards the eye by the bias, so the plane they are clipped by moves that far too: an outline that sits on
        // the plane (the section is inset by 1e-4 mm) stays, one on the cut-away side (an old section) goes.
        var clip = ClipUniforms(frame.clip)
        if clip.enabled != 0 { clip.plane.w -= Float(edgeDepthBias(frame)) }
        drawLines(lines.buffer, count: lines.count, uniforms, depth: pipelines.depthTest, style: style, clip: clip, encoder)
    }
}
#endif

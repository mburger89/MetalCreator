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
        var instances: [LineInstance] = []
        for cap in section.caps {
            var vertices: [SectionVertex] = []
            for index in cap.triangles where Int(index) < cap.positions.count {
                vertices.append(SectionVertex(position: SIMD4(GPUGeometry.float3(cap.positions[Int(index)]), 1)))
            }
            vertices.removeLast(vertices.count % 3)
            if let buffer = GPUBuffers.make(device, vertices) {
                caps.append(SectionBuffers.CapBuffer(buffer: buffer, count: vertices.count, angle: cap.hatchAngle))
            }
            for outline in cap.outlines {
                for (a, b) in zip(outline, outline.dropFirst()) {
                    instances.append(LineInstance(a: GPUGeometry.float3(a), b: GPUGeometry.float3(b),
                                                  color: frame.palette.sectionEdge, width: 1, id: 0))
                }
            }
        }
        let lines = GPUBuffers.make(device, instances).map { (buffer: $0, count: instances.count) }
        let built = SectionBuffers(key: key, caps: caps, lines: lines)
        sectionCache = built
        return built
    }

    func capUniforms(_ section: ViewportSection, angle: Double, frame: ViewportFrame) -> SectionUniforms {
        let millimetres = Float(CameraMath.millimetresPerPoint(frame.pose, size: frame.size))
        return SectionUniforms(
            fill: frame.palette.sectionFill, hatch: frame.palette.sectionHatch,
            origin: SIMD4(GPUGeometry.float3(section.plane.origin), 0),
            axisU: SIMD4(GPUGeometry.float3(section.plane.xAxis), 0),
            axisV: SIMD4(GPUGeometry.float3(section.plane.yAxis), 0),
            hatchParams: SIMD4(Float(ViewportSection.hatchSpacingPoints) * millimetres,
                               Float(ViewportSection.hatchLinePoints) * millimetres,
                               Float(cos(angle)), Float(sin(angle))),
            depthParams: SIMD4(capDepthBias(frame), 0, 0, 0))
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
            var draw = capUniforms(section, angle: cap.angle, frame: frame)
            encoder.setVertexBuffer(cap.buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&draw, length: MemoryLayout<SectionUniforms>.stride, index: 2)
            encoder.setFragmentBytes(&draw, length: MemoryLayout<SectionUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cap.count)
        }
    }

    /// The cap outlines through the line pipeline: tested against the depth, never clipped by the line shader.
    func drawSectionOutlines(_ frame: ViewportFrame, _ uniforms: FrameUniforms, scale: Float,
                             _ encoder: any MTLRenderCommandEncoder) {
        guard let lines = sectionBuffers(for: frame)?.lines else { return }
        let style = LineUniforms(widthOverride: 1.25 * scale, depthBias: Float(edgeDepthBias(frame)), padding0: 0, padding1: 0)
        // The lines move towards the eye by the bias, so the plane they are clipped by moves that far too: an outline that sits on
        // the plane (the section is inset by 1e-4 mm) stays, one on the cut-away side (an old section) goes.
        var clip = ClipUniforms(frame.clip)
        if clip.enabled != 0 { clip.plane.w -= Float(edgeDepthBias(frame)) }
        drawLines(lines.buffer, count: lines.count, uniforms, depth: pipelines.depthTest, style: style, clip: clip, encoder)
    }
}
#endif

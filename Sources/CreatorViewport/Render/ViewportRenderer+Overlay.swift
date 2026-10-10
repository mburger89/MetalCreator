import Metal

extension ViewportRenderer {
    /// The host's overlay over the scene and the ghosts, whatever their depth (sketcher spec §8: the sketch is drawn
    /// over the dimmed model): its fills first, then its grid, lines and points on top of them.
    func drawOverlay(_ frame: ViewportFrame, _ uniforms: FrameUniforms, scale: Float, _ encoder: any MTLRenderCommandEncoder) {
        drawFills(frame, uniforms, encoder)
        guard let overlay = overlayInstances(for: frame, scale: scale) else { return }
        drawLines(overlay.buffer, count: overlay.count, uniforms, depth: pipelines.depthAlways, style: Self.plainLines, encoder)
    }

    private func drawFills(_ frame: ViewportFrame, _ uniforms: FrameUniforms, _ encoder: any MTLRenderCommandEncoder) {
        guard let fills = fillVertices(for: frame) else { return }
        var copy = uniforms
        encoder.setRenderPipelineState(pipelines.fill)
        encoder.setDepthStencilState(pipelines.depthAlways)
        encoder.setVertexBuffer(fills.buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&copy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: fills.count)
    }

    /// The frame's fill triangles in its palette, kept until the fills or the palette change.
    func fillVertices(for frame: ViewportFrame) -> (buffer: any MTLBuffer, count: Int)? {
        guard !frame.overlay.fills.isEmpty else { return nil }
        let key = FillBufferKey(fills: frame.overlay.fills, palette: frame.palette)
        if let cached = fillBuffer, cached.key == key { return (cached.buffer, cached.count) }
        let vertices = OverlayGeometry.fillVertices(frame.overlay.fills, palette: frame.palette)
        guard let buffer = GPUBuffers.make(device, vertices) else {
            fillBuffer = nil
            return nil
        }
        fillBuffer = (key, buffer, vertices.count)
        return (buffer, vertices.count)
    }

    /// The frame's overlay in its palette, kept until the overlay, the camera, the scale or the palette change.
    func overlayInstances(for frame: ViewportFrame, scale: Float) -> (buffer: any MTLBuffer, count: Int)? {
        guard !frame.overlay.isEmpty else { return nil }
        let key = OverlayBufferKey(overlay: frame.overlay, pose: frame.pose, size: frame.size, gridSpacing: frame.gridSpacing,
                                   scale: scale, palette: frame.palette)
        if let cached = overlayBuffer, cached.key == key { return (cached.buffer, cached.count) }
        let instances = OverlayGeometry.instances(frame.overlay, pose: frame.pose, size: frame.size,
                                                  gridSpacing: frame.gridSpacing, scale: scale, palette: frame.palette)
        guard let buffer = GPUBuffers.make(device, instances) else {
            overlayBuffer = nil
            return nil
        }
        overlayBuffer = (key, buffer, instances.count)
        return (buffer, instances.count)
    }
}

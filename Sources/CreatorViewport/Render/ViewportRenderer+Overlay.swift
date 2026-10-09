import Metal

extension ViewportRenderer {
    /// The host's overlay over the scene and the ghosts, whatever their depth (sketcher spec §8: the sketch is drawn
    /// over the dimmed model).
    func drawOverlay(_ frame: ViewportFrame, _ uniforms: FrameUniforms, scale: Float, _ encoder: any MTLRenderCommandEncoder) {
        guard let overlay = overlayInstances(for: frame, scale: scale) else { return }
        drawLines(overlay.buffer, count: overlay.count, uniforms, depth: pipelines.depthAlways, style: Self.plainLines, encoder)
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

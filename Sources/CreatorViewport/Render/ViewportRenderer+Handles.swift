import Metal

extension ViewportRenderer {
    /// The frame's handles in its palette, kept until the handles, the scale or the palette change.
    func handleInstances(for frame: ViewportFrame, scale: Float) -> (buffer: any MTLBuffer, count: Int)? {
        if let cached = handleBuffer, cached.handles == frame.handles, cached.scale == scale, handlePalette == frame.palette {
            return (cached.buffer, cached.count)
        }
        handlePalette = frame.palette
        let instances = GPUGeometry.handleInstances(frame.handles, scale: scale, palette: frame.palette)
        guard let buffer = GPUBuffers.make(device, instances) else {
            handleBuffer = nil
            return nil
        }
        handleBuffer = (frame.handles, scale, buffer, instances.count)
        return (buffer, instances.count)
    }
}

import Metal

extension ViewportRenderer {
    /// The triad's instances in GPU memory, kept until the scale or the palette change.
    func triadInstances(scale: Float, palette: ViewportPalette) -> (buffer: any MTLBuffer, count: Int)? {
        if let cached = triadBuffer, cached.scale == scale, cached.palette == palette { return (cached.buffer, cached.count) }
        let instances = GPUGeometry.triadInstances(scale: scale, palette: palette)
        guard let buffer = GPUBuffers.make(device, instances) else {
            triadBuffer = nil
            return nil
        }
        triadBuffer = (scale, palette, buffer, instances.count)
        return (buffer, instances.count)
    }
}

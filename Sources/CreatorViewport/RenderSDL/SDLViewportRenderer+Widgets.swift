#if canImport(MetalUISDLGPU)
import CreatorGeometry
import MetalUISDLGPU

extension SDLViewportRenderer {
    /// The view cube in its own square at the top-left, or `nil` when it is hidden, does not fit the target, or its face names or
    /// tiles could not be made. A cube is convex, so back-face culling replaces a depth test, and a face turned away hides its name.
    func planCube(_ frame: ViewportFrame, scale: Double, width: Int, height: Int,
                  _ uploader: SDLViewportUploader) -> SDLFramePlan.Cube? {
        guard frame.showsViewCube else { return nil }
        let layout = frame.cube
        let x = layout.origin.x * scale, y = layout.origin.y * scale, side = layout.side * scale
        guard x >= 0, y >= 0, x + side <= Double(width), y + side <= Double(height),
              let labels = cube.labelTexture(uploader: uploader), let sampler = cube.sampler,
              let tiles = cube.vertices(hovered: frame.hoveredCubeRegion, pose: frame.pose, palette: frame.palette,
                                        uploader: uploader) else { return nil }
        let camera = GPUGeometry.frameUniforms(layout.widgetPose(frame.pose), size: layout.widgetSize, sceneRadius: 2,
                                               pixelWidth: Int(side), pixelHeight: Int(side))
        return SDLFramePlan.Cube(tiles: tiles.buffer, count: tiles.count, labels: labels, sampler: sampler,
                                 ink: frame.palette.cubeLabel,
                                 viewport: SDLFramePlan.WidgetViewport(x: Float(x), y: Float(y), side: Float(side), camera: camera))
    }

    /// The axis triad in its own square at the bottom-left, or `nil` when it does not fit the target.
    func planTriad(_ frame: ViewportFrame, scale: Double, width: Int, height: Int,
                   _ uploader: SDLViewportUploader) -> SDLFramePlan.Triad? {
        let triad = frame.triad
        let origin = triad.origin(in: frame.size)
        let x = origin.x * scale, y = origin.y * scale, side = triad.side * scale
        guard x >= 0, y >= 0, x + side <= Double(width), y + side <= Double(height),
              let lines = triadInstances(scale: Float(scale), palette: frame.palette, uploader) else { return nil }
        let camera = GPUGeometry.frameUniforms(triad.widgetPose(frame.pose),
                                               size: ViewportSize(width: triad.side, height: triad.side), sceneRadius: 2,
                                               pixelWidth: Int(side), pixelHeight: Int(side))
        return SDLFramePlan.Triad(
            lines: SDLFramePlan.Lines(buffer: lines.buffer, count: lines.count, style: Self.plainLines),
            viewport: SDLFramePlan.WidgetViewport(x: Float(x), y: Float(y), side: Float(side), camera: camera))
    }

    /// The triad's instances in GPU memory, kept until the scale or the palette change.
    private func triadInstances(scale: Float, palette: ViewportPalette,
                                _ uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        if let cached = triadBuffer, cached.scale == scale, cached.palette == palette { return (cached.buffer, cached.count) }
        let instances = GPUGeometry.triadInstances(scale: scale, palette: palette)
        guard let buffer = uploader.storageBuffer(instances) else {
            triadBuffer = nil
            return nil
        }
        triadBuffer = (scale, palette, buffer, instances.count)
        return (buffer, instances.count)
    }

    /// Draws the cube into its square: the viewport maps clip space into it, and its camera is the cube's own.
    func drawCube(_ cube: SDLFramePlan.Cube, in pass: SDLGPURenderPass) {
        let recorder = SDLPassRecorder(pass: pass, camera: uniformBytes(cube.viewport.camera))
        pass.setViewport(x: cube.viewport.x, y: cube.viewport.y, width: cube.viewport.side, height: cube.viewport.side)
        recorder.bind(pipelines.cube)
        pass.bindVertexStorageBuffers([cube.tiles])
        pass.bindFragmentSamplers([(texture: cube.labels, sampler: cube.sampler)])
        pass.pushFragmentUniform(uniformBytes(cube.ink), at: 0)
        pass.draw(vertexCount: cube.count)
    }

    /// Draws the triad into its square with its own camera.
    func drawTriad(_ triad: SDLFramePlan.Triad, in pass: SDLGPURenderPass) {
        let recorder = SDLPassRecorder(pass: pass, camera: uniformBytes(triad.viewport.camera))
        pass.setViewport(x: triad.viewport.x, y: triad.viewport.y, width: triad.viewport.side, height: triad.viewport.side)
        drawLines(triad.lines, pipeline: pipelines.lineAlways, in: recorder)
    }
}
#endif

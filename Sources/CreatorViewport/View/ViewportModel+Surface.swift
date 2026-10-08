import Metal
import MetalUI

extension ViewportModel {
    /// Why the viewport's GPU objects couldn't be made, if they couldn't. The surface is then cleared to dark red.
    public var gpuFailureMessage: String? { gpuFailure }

    /// The `MetalView` draw (spec §6.3). It runs on the main actor inside MetalUI's frame, after the tracked build.
    /// It records the surface's size, makes the GPU objects on first use, and encodes into the frame's own command
    /// buffer. It writes only untracked state (a draw must never dirty the window), and it never commits.
    func draw(_ context: MetalDrawContext) {
        let scale = context.scaleFactor > 0 ? Double(context.scaleFactor) : 1
        // Untracked, and a first real size schedules (not performs) any pending first framing.
        recordViewSize(ViewportSize(width: Double(context.pixelSize.width.value) / scale,
                                    height: Double(context.pixelSize.height.value) / scale))
        guard let renderer = renderer(for: context.device) else {
            context.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
            return
        }
        renderer.encode(frame(at: clock.now()), into: context.target, scale: scale, commandBuffer: context.commandBuffer)
    }

    private func renderer(for device: any MTLDevice) -> ViewportRenderer? {
        if let gpuRenderer { return gpuRenderer }
        guard gpuFailure == nil else { return nil }
        do {
            let renderer = try ViewportRenderer(device: device)
            let picker = try ViewportPicker(renderer: renderer)
            gpuRenderer = renderer
            pick = { [weak self] point in
                guard let self else { return nil }
                return picker.pick(at: point, in: frame(at: clock.now()))
            }
            return renderer
        } catch {
            gpuFailure = String(describing: error)
            return nil
        }
    }
}

#if canImport(Metal)
import Metal
import MetalUI

extension ViewportModel {
    /// The `MetalView` draw (spec §6.3). It runs on the main actor inside MetalUI's frame, after the tracked build.
    /// It makes the GPU objects on first use and encodes into the frame's own command buffer. It writes only untracked
    /// state (a draw must never dirty the window), and it never commits. The view's size is not recorded here: it
    /// comes from `ViewportView`'s `onGeometryChange`.
    func draw(_ context: MetalDrawContext) {
        let scale = context.scaleFactor > 0 ? Double(context.scaleFactor) : 1
        guard let metal = metalBackend(for: context.device) else {
            context.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
            return
        }
        metal.renderer.encode(frame(at: clock.now()), into: context.target, scale: scale, commandBuffer: context.commandBuffer)
    }

    private func metalBackend(for device: any MTLDevice) -> MetalViewportBackend? {
        if let existing = backend as? MetalViewportBackend { return existing }
        guard gpuFailure == nil else { return nil }
        do {
            let made = try MetalViewportBackend(device: device)
            install(made)
            return made
        } catch {
            gpuFailure = String(describing: error)
            return nil
        }
    }
}
#endif

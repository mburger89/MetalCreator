#if canImport(MetalUISDLGPU)
import MetalUI
import MetalUISDL
import MetalUISDLGPU

extension ViewportModel {
    /// The `GPUSurface` draw on SDL (spec §6.3; the Metal `draw` is `ViewportModel+Surface`). It runs on the main actor inside MetalUI's
    /// frame, after the tracked build. It makes the GPU objects on first use and encodes into the frame's own command buffer, and
    /// never submits it. It writes only untracked state (a draw must never dirty the window). If the GPU objects can't be made,
    /// the surface is cleared to the dark red the Metal viewport shows.
    func draw(_ context: any GPUSurfaceContext) {
        guard let sdl = context as? SDLGPUDrawContext else {
            context.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
            return
        }
        let view = sdl.view
        guard let sdlBackend = sdlBackend(for: view.device) else {
            sdl.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
            return
        }
        sdlBackend.draw(frame(at: clock.now()), in: view, scale: sdl.scaleFactor > 0 ? Double(sdl.scaleFactor) : 1)
    }

    private func sdlBackend(for device: SDLGPUDevice) -> SDLViewportBackend? {
        if let existing = backend as? SDLViewportBackend { return existing }
        guard gpuFailure == nil else { return nil }
        do {
            let made = try SDLViewportBackend(device: device)
            install(made)
            return made
        } catch {
            gpuFailure = String(describing: error)
            return nil
        }
    }
}
#elseif !canImport(Metal)
import MetalUI

extension ViewportModel {
    /// The `GPUSurface` draw in a build with neither Metal nor MetalUI's SDL GPU layer: it clears the surface to the colour a viewport
    /// whose GPU objects could not be made shows on macOS.
    func draw(_ context: any GPUSurfaceContext) {
        context.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
    }
}
#endif

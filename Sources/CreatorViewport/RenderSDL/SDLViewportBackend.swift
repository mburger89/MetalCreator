#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// The Linux and Windows backend: the SDL_GPU renderer and the picker that reads its ID buffer back. The device is the window
/// renderer's, borrowed from the first draw, so it is kept no longer than the window.
@MainActor
final class SDLViewportBackend: ViewportBackend {
    let renderer: SDLViewportRenderer
    let picker: SDLViewportPicker

    init(renderer: SDLViewportRenderer) {
        self.renderer = renderer
        picker = SDLViewportPicker(renderer: renderer)
    }

    convenience init(device: SDLGPUDevice) throws {
        self.init(renderer: try SDLViewportRenderer(device: device, library: try SDLViewportShaders.library()))
    }

    /// No view cube or triad is drawn yet (task 10 draws them): the model must not hit-test a cube nobody can see.
    var drawsWidgets: Bool { false }

    var drawnFrames: Int { renderer.encodedPasses }

    var onPickReady: (@MainActor () -> Void)? {
        get { picker.onReady }
        set { picker.onReady = newValue }
    }

    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
        picker.pick(at: point, in: frame)
    }

    func isPickPending(for frame: ViewportFrame) -> Bool {
        picker.isPending(for: frame)
    }

    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget? {
        await picker.pickWhenReady(at: point, in: frame)
    }

    /// Draws `frame` into the surface's target, in the frame's own command buffer, then starts the ID pass for it if it is for a view
    /// the picker has no buffer for. The ID pass is a batch of its own, submitted after the frame's buffer.
    func draw(_ frame: ViewportFrame, in view: SDLGPUFrameView, scale: Double) {
        renderer.encode(frame, into: view.target, scale: scale, commandBuffer: view.commandBuffer)
        picker.schedule(frame)
    }
}
#endif

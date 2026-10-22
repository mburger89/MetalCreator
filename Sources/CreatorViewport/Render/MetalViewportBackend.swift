#if canImport(Metal)
import Metal

/// The macOS backend: the Metal renderer and the picker that renders and reads back its ID buffer on its own queue. A pick is
/// answered at once (it waits for the GPU, as `ViewportPicker` always did), so nothing is ever pending.
@MainActor
final class MetalViewportBackend: ViewportBackend {
    let renderer: ViewportRenderer
    let picker: ViewportPicker
    var onPickReady: (@MainActor () -> Void)?

    init(device: any MTLDevice) throws {
        renderer = try ViewportRenderer(device: device)
        picker = try ViewportPicker(renderer: renderer)
    }

    var drawnFrames: Int { renderer.encodedPasses }

    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
        picker.pick(at: point, in: frame)
    }
}
#endif

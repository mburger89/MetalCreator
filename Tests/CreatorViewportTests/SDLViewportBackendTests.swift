#if canImport(MetalUISDLGPU)
import Testing
@testable import CreatorViewport

/// What the SDL backend tells the model about itself. (Its draw and its picks are `SDLRenderTests` and `SDLPickerTests`.)
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLViewportBackendTests {
    @Test func theBackendDrawsNoCubeYetSoTheModelDoesNotHitTestOne() throws {
        let rig = try SDLRenderRig()
        let backend = SDLViewportBackend(renderer: rig.renderer)
        #expect(!backend.drawsWidgets, "until task 10 there is no cube on screen, so none may rotate the camera")
    }
}
#endif

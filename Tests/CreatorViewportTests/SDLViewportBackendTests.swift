#if canImport(MetalUISDLGPU)
import Testing
@testable import CreatorViewport

/// What the SDL backend tells the model about itself. (Its draw and its picks are `SDLRenderTests` and `SDLPickerTests`.)
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLViewportBackendTests {
    @Test func theBackendDrawsTheCubeSoTheModelMayHitTestIt() throws {
        let rig = try SDLRenderRig()
        let backend = SDLViewportBackend(renderer: rig.renderer)
        #expect(backend.drawsWidgets, "task 8 had no cube to draw and said false; from task 10 the cube and triad are drawn")
    }
}
#endif

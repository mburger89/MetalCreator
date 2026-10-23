#if canImport(MetalUISDLGPU)
extension HLSLImplicitEngine {
    /// The implicit engine of Linux and Windows (plan xp-c task 11): the HLSL engine over an owned, headless SDL_GPU device, its kernels compiled while
    /// the app runs (`SDLRuntimeKernels`). The backend is made on first use inside the actor, never on the main actor.
    public static let sdl = HLSLImplicitEngine(name: SDLComputeBackend.platformName,
                                               backend: { SDLComputeBackend.make(kernels: SDLRuntimeKernels()) })
}
#endif

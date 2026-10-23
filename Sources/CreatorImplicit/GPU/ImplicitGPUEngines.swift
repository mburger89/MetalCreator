/// Which GPU engine this platform has. The only place outside the engines themselves that knows a platform's GPU API, and it names no
/// type of one: it only asks `canImport`.
public enum ImplicitGPUEngines {
    /// The engine for this machine's GPU, or `nil` where there is none (a platform with neither Metal nor MetalUI's SDL_GPU layer).
    public static var platformDefault: (any ImplicitGPUEngine)? {
        #if canImport(Metal)
        MetalImplicitEngine.shared
        #elseif canImport(MetalUISDLGPU)
        HLSLImplicitEngine.sdl
        #else
        nil
        #endif
    }
}

/// Which GPU engine this platform has. The only place outside the engines themselves that knows a platform's GPU API, and it names no
/// type of one: it only asks `canImport`.
public enum ImplicitGPUEngines {
    /// The engine for this machine's GPU, or `nil` where there is none (no device, or a platform with no engine yet).
    public static var platformDefault: (any ImplicitGPUEngine)? {
        #if canImport(Metal)
        MetalImplicitEngine.shared
        #else
        nil
        #endif
    }
}

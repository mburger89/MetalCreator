/// `MetalCreator --self-test`'s line about the implicit engine (plan xp-c): the platform's engine and its device, or why evaluation is on the CPU. It
/// never fails the self-test by itself: a machine without a GPU engine is a supported machine (D11). `compilerSelfTest()` is MetalUI's compiler
/// self-test, which does fail a package that ships without the compiler libraries.
public enum ImplicitEngineCheck {
    public static func run() async -> String {
        guard let engine = ImplicitGPUEngines.platformDefault else {
            return "the CPU (no GPU engine on this platform)"
        }
        switch await engine.availability {
        case .available: return "\(engine.name) on \(await engine.deviceName)"
        case .absent(let why): return "the CPU (\(why))"
        case .broken(let why): return "the CPU, with a warning (\(why))"
        }
    }

    /// Whether `--self-test` checks the implicit engine's run-time compiler: Linux and Windows, where the engine compiles its HLSL through MetalUI.
    public static var hasRuntimeCompiler: Bool {
        #if canImport(MetalUISDLGPU)
        true
        #else
        false
        #endif
    }

    /// MetalUI's compiler self-test (`SDLCompilerSelfTest`); it fails `--self-test` in a package that ships without the compiler's libraries.
    public static func compilerSelfTest() async throws -> String {
        #if canImport(MetalUISDLGPU)
        try await SDLCompilerSelfTest.run()
        #else
        "not needed: Metal compiles the implicit engine's kernels"
        #endif
    }
}

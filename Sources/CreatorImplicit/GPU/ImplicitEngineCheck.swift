/// `MetalCreator --self-test`'s line about the implicit engine (plan xp-c): the platform's engine and its device, or why evaluation is on the CPU. It
/// never fails the self-test by itself: a machine without a GPU engine is a supported machine (D11). Task 12 adds MetalUI's compiler self-test, which
/// does fail a package that ships without the compiler libraries.
public enum ImplicitEngineCheck {
    public static func run() async -> String {
        guard let engine = ImplicitGPUEngines.platformDefault else {
            return "the CPU (no GPU engine on this platform yet: SDL_GPU run-time compilation waits for MetalUI XP-G25)"
        }
        switch await engine.availability {
        case .available: return "\(engine.name) on \(await engine.deviceName)"
        case .absent(let why): return "the CPU (\(why))"
        case .broken(let why): return "the CPU, with a warning (\(why))"
        }
    }
}

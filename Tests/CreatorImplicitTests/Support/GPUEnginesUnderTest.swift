import Foundation
@testable import CreatorImplicit

/// The GPU engines this machine can test, by name (plan xp-c): "Metal" on a Mac with a device; the HLSL engine as "Metal (HLSL)" on a Mac where the
/// generated kernels were compiled offline or MetalUI's run-time compiler loads, as "Vulkan" (Linux) and "Direct3D 12" (Windows) over SDL_GPU: compiled at run time as the app
/// does where MetalUI's compiler loads, else on the kernels compiled offline.
enum GPUEnginesUnderTest {
    static let hlslState: ComputeBackendState = {
        #if canImport(MetalUISDLGPU)
        // Compiled at run time as the app does where MetalUI's compiler loads (task 11), else the kernels compiled offline (task 3).
        if RuntimeCompileUnderTest.isAvailable { return RuntimeCompileUnderTest.state }
        return SDLComputeBackend.make(kernels: SDLPrecompiledKernels(directory: GeneratedKernels.compiled))
        #elseif canImport(Metal)
        // The same on a Mac where MetalUIShaderRuntime loads (gap XP-G27): the MSL compiled at run time, else the kernels compiled offline.
        if RuntimeCompileUnderTest.isAvailable { return RuntimeCompileUnderTest.state }
        return MSLComputeBackend.state
        #else
        return .absent("no backend for the HLSL engine on this platform")
        #endif
    }()

    static var hlslName: String {
        if case .ready(let backend) = hlslState { return backend.name }
        return "HLSL"
    }

    /// A fresh HLSL engine over the shared backend (its own caches, hooks, tuning and epoch), or `nil`.
    static func makeHLSL(dispatchSize: Int = HLSLImplicitEngine.pointsPerDispatch) -> HLSLImplicitEngine? {
        guard case .ready = hlslState else { return nil }
        let state = hlslState
        return HLSLImplicitEngine(name: hlslName, backend: { state }, dispatchSize: dispatchSize)
    }

    static let hlsl: HLSLImplicitEngine? = makeHLSL()

    static let names: [String] = {
        var names: [String] = []
        #if canImport(Metal)
        if MetalImplicitEngine.shared != nil { names.append("Metal") }
        #endif
        if hlsl != nil { names.append(hlslName) }
        return names
    }()

    struct Missing: Error, CustomStringConvertible {
        let description: String
    }

    static func engine(_ name: String) throws -> any ImplicitGPUEngine {
        #if canImport(Metal)
        if name == "Metal", let engine = MetalImplicitEngine.shared { return engine }
        #endif
        if name == hlslName, let hlsl { return hlsl }
        throw Missing(description: "no engine named \(name) here")
    }

    static var unavailableReason: String { hlslState.description }
}

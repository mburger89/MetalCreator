import Foundation
@testable import CreatorImplicit

/// The GPU engines this machine can test, by name (plan xp-c): "Metal" on a Mac with a device; the HLSL engine as "Metal (HLSL)" on a Mac where the
/// generated kernels were compiled offline, as "Vulkan" (Linux) and "Direct3D 12" (Windows) over SDL_GPU: on kernels compiled offline until task 11,
/// then compiled at run time as the app does.
enum GPUEnginesUnderTest {
    static let hlslState: ComputeBackendState = {
        #if canImport(MetalUISDLGPU) && false
        return SDLComputeBackend.make(kernels: SDLPrecompiledKernels(directory: GeneratedKernels.compiled))
        #elseif canImport(Metal)
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

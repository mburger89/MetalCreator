import Foundation
@testable import CreatorImplicit

/// MetalUI's run-time compiler where this test process can load it (plan xp-c task 11, gaps XP-G25, XP-G27): the Linux image and the Windows job name the
/// library with `METALUI_SHADERCROSS_LIB` and run the result on SDL_GPU; a Mac names a macOS SDL3_shadercross directory (with `libSDL3.0.dylib` beside
/// it) the same way and runs the MSL compiled at run time (`RuntimeMSLKernels`) on `MSLComputeBackend`. One backend for the process, made once. Where the
/// library does not load, `.absent` with MetalUI's error and the tests skip: the Mac's HLSL then runs as the offline MSL (`GeneratedKernels`).
enum RuntimeCompileUnderTest {
    static let hasSDLGPU: Bool = {
        #if canImport(MetalUISDLGPU)
        return true
        #else
        return false
        #endif
    }()

    static let state: ComputeBackendState = {
        #if canImport(MetalUISDLGPU)
        return SDLComputeBackend.make(kernels: SDLRuntimeKernels())
        #elseif canImport(Metal) && canImport(MetalUIShaderRuntime)
        let kernels = RuntimeMSLKernels()
        if let unavailable = kernels.unavailability { return unavailable }
        return MSLComputeBackend.make(runtimeKernels: kernels)
        #else
        return .absent("no run-time shader compiler on this platform")
        #endif
    }()

    static var isAvailable: Bool {
        if case .ready = state { return true }
        return false
    }
}

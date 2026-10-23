import Foundation
@testable import CreatorImplicit

/// MetalUI's run-time compiler where this test process can load it (plan xp-c task 11, gap XP-G25): the Linux image and the Windows job name the library
/// with `METALUI_SHADERCROSS_LIB`. One backend for the process, made once. A Mac never has it: MetalUI's compiler is in its SDL layer, which a macOS build
/// does not ask for, so the Mac's HLSL runs as the offline MSL (`GeneratedKernels`, `MSLComputeBackend`; gap XP-G27).
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
        #else
        return .absent("MetalUI's run-time compiler is in its SDL layer, which a macOS build does not build "
            + "(plan xp-c Global Constraints, gap XP-G27)")
        #endif
    }()

    static var isAvailable: Bool {
        if case .ready = state { return true }
        return false
    }
}

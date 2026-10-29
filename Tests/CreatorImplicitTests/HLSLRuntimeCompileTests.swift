import Foundation
import Testing
@testable import CreatorImplicit

/// Run-time compilation of the generated HLSL (plan xp-c task 11, MetalUI XP-G25): what the app does on Linux and Windows.
struct HLSLRuntimeCompileTests {
    /// Review Focus 2: a compiler library that does not load is `.broken`, naming the path tried, and a solid then runs on the CPU with the warning.
    /// MetalUI loads the library once per process: when an earlier test loaded it, the explicit path is refused as `libraryAlreadyLoaded`, which names
    /// the requested path too; the package checks (task 12) cover a process that never had it.
    @Test(.enabled(if: RuntimeCompileUnderTest.hasSDLGPU,
                   "MetalUI's run-time compiler is in its SDL layer, which a macOS build does not build"))
    func aMissingCompilerLibraryIsBrokenAndNamesWhatItTried() async {
        #if canImport(MetalUISDLGPU)
        let missing = FileManager.default.temporaryDirectory.appending(path: "no-shadercross-\(UUID().uuidString)")
            .appending(path: "libSDL3_shadercross.so.0").path
        let kernels = SDLRuntimeKernels(libraryPath: missing)
        guard case .broken(let why) = kernels.unavailability else {
            Issue.record("a compiler library that is not there was not reported broken")
            return
        }
        #expect(why.contains(missing), "\(why)")
        let engine = HLSLImplicitEngine(name: SDLComputeBackend.platformName, backend: { SDLComputeBackend.make(kernels: kernels) })
        let selection = await ImplicitEvaluators.make(for: .sphere(radius: 1), choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "CPU")
        if case .absent = await engine.availability {
            #expect(selection.warning == nil, "no SDL_GPU device: the CPU, silently (X-C4)")
        } else {
            #expect(selection.warning == ImplicitEvaluators.cpuWarning)
            #expect(selection.diagnostic?.contains(missing) == true, "\(selection.diagnostic ?? "no diagnostic")")
        }
        #endif
    }

    /// Review Focus 1: a source DXC refuses is `ImplicitCompileError.engine` with DXC's own text, so the selection falls back to the CPU with it.
    @Test(.enabled(if: RuntimeCompileUnderTest.isAvailable, "needs MetalUI's run-time compiler library"))
    func aSourceTheCompilerRefusesRunsOnTheCPUWithItsDiagnostic() async throws {
        guard case .ready(let backend) = RuntimeCompileUnderTest.state else {
            Issue.record("\(RuntimeCompileUnderTest.state)")
            return
        }
        let broken = KernelSource(kernel: .evaluate, text: HLSLShaderLibrary.prelude + "\n[numthreads(64, 1, 1)] void main( {")
        let error = await #expect(throws: ImplicitCompileError.self) { _ = try await backend.makePipeline(broken) }
        guard case .engine(let text) = error else {
            Issue.record("not an engine error: \(String(describing: error))")
            return
        }
        #expect(text.contains("HLSL to SPIR-V failed"), "\(text)")
        #expect(!text.contains("the compiler gave no message"), "DXC's diagnostics were lost: \(text)")
    }

    /// The app's engine compiles at run time and agrees with the CPU (the agreement suites then run on it too, through `GPUEnginesUnderTest`).
    @Test(.enabled(if: RuntimeCompileUnderTest.isAvailable, "needs MetalUI's run-time compiler library"))
    func thePlatformEngineCompilesAtRunTime() async throws {
        let engine = try #require(ImplicitGPUEngines.platformDefault)
        #expect(await engine.availability == .available)
        let program = try await engine.compile(.sphere(radius: 5))
        let values = try await GPUBatchEvaluator(engine: engine, program: program).evaluate([SIMD3(8, 0, 0)])
        #expect(values.count == 1 && abs(values[0] - 3) < 1e-5)
    }

    /// A kernel source is compiled once per engine: the same shape twice compiles nothing the second time (Review Focus 3, at run time).
    @Test(.enabled(if: RuntimeCompileUnderTest.isAvailable, "needs MetalUI's run-time compiler library"))
    func aSecondCompileOfTheSameShapeCompilesNothing() async throws {
        let state = RuntimeCompileUnderTest.state
        let engine = HLSLImplicitEngine(name: "run-time", backend: { state })
        _ = try await engine.compile(.sphere(radius: 2))
        _ = try await engine.compile(.sphere(radius: 7))
        #expect(await engine.compileCount == 1)
    }
}

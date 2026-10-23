#if canImport(MetalUISDLGPU)
import Foundation
import Testing
@testable import CreatorImplicit

/// The SDL_GPU backend itself (Linux and Windows): a kernel missing from a provider, and a batch's order.
struct SDLComputeBackendTests {
    /// The ready backend, or a failure saying why it is not (a backend that is not ready must not pass these tests vacuously).
    static func readyBackend(_ state: ComputeBackendState) throws -> any ImplicitComputeBackend {
        guard case .ready(let backend) = state else {
            throw GeneratedKernelError.backendNotReady(String(describing: state))
        }
        return backend
    }

    @Test(.enabled(if: GPUEnginesUnderTest.hlsl != nil, "needs an SDL_GPU device"))
    func aKernelTheProviderDoesNotHaveIsUnsupportedNamingTheScript() async throws {
        let empty = SDLPrecompiledKernels(directory: FileManager.default.temporaryDirectory)
        let backend = try Self.readyBackend(SDLComputeBackend.make(kernels: empty))
        let source = try #require(try ImplicitCompiler.compileHLSL(.sphere(radius: 1)).kernels[.evaluate])
        await #expect {
            _ = try await backend.makePipeline(source)
        } throws: { String(describing: $0).contains("scripts/linux-test.sh kernels") }
    }

    /// A dispatch sees what the uploads before it wrote, and the download sees what it wrote: each in its own pass.
    @Test(.enabled(if: GPUEnginesUnderTest.hlsl != nil, "needs an SDL_GPU device"))
    func aBatchsUploadsDispatchesAndDownloadsRunInOrder() async throws {
        let backend = try Self.readyBackend(GPUEnginesUnderTest.hlslState)
        let program = try ImplicitCompiler.compileHLSL(.sphere(radius: 2))
        let engine = try #require(GPUEnginesUnderTest.makeHLSL())
        let solid = try await engine.buffers(for: program, on: backend)
        let pipeline = try await backend.makePipeline(try #require(program.kernels[.evaluate]))
        let input = try backend.makeBuffer(length: 24)
        let output = try backend.makeBuffer(length: 8)
        var parameters = solid.parameters
        parameters.count = 2
        let dispatch = ComputeDispatch(kernel: .evaluate, pipeline: pipeline, parameters: parameters,
                                       readOnly: [solid.floats, solid.ints, input], readWrite: [output], threads: 2)
        let upload = ComputeUpload(bytes: ComputeBytes.bytes(of: [Float](arrayLiteral: 5, 0, 0, 0, 0, 1)), buffer: input)
        let read = try await backend.run(ComputeBatch(
            uploads: [upload], dispatches: [dispatch], downloads: [ComputeDownload(buffer: output, length: 8)]))
        let values = ComputeBytes.values(try #require(read.first), as: Float.self)
        #expect(values.count == 2 && abs(values[0] - 3) < 1e-6 && abs(values[1] + 1) < 1e-6)
    }
}
#endif

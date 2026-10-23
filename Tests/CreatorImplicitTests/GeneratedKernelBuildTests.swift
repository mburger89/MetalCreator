import Foundation
import Testing
@testable import CreatorImplicit

/// Every generated kernel of every test shape compiled offline (plan xp-c, task 3): DXC took the generator's output, and each reflection has the
/// buffers `ImplicitKernel.bindings` says. Required on Linux (the test step compiles them first); on a Mac where `scripts/linux-test.sh kernels` ran.
struct GeneratedKernelBuildTests {
    @Test func everyGeneratedKernelCompiledWithItsBindings() throws {
        #if canImport(MetalUISDLGPU)
        let required = true
        #else
        let required = false
        #endif
        guard required || FileManager.default.fileExists(atPath: GeneratedKernels.compiled.path) else { return }
        for source in GeneratedKernels.sources {
            let stem = GeneratedKernels.compiled.appending(path: "\(source.digest).comp")
            for blob in ["spv", "dxil", "msl"] {
                let size = (try? Data(contentsOf: stem.appendingPathExtension(blob)).count) ?? 0
                #expect(size > 0, "\(source.kernel.rawValue) \(source.digest).\(blob) is missing: \(GeneratedKernels.remedy)")
            }
            let json = try? JSONSerialization.jsonObject(with: Data(contentsOf: stem.appendingPathExtension("json")))
            let reflection = json as? [String: Int]
            let name = source.kernel.rawValue
            #expect(reflection?["readonly_storage_buffers"] == source.kernel.bindings.readOnly, "\(name): a read-only buffer was dropped")
            #expect(reflection?["readwrite_storage_buffers"] == source.kernel.bindings.readWrite, "\(name): a read-write buffer dropped")
            #expect(reflection?["uniform_buffers"] == 1)
            #expect(reflection?["threadcount_x"] == ImplicitKernel.threadsPerGroup)
        }
    }
}

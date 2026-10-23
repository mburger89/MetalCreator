import Testing
@testable import CreatorImplicit

/// What `--self-test` says about the implicit engine (plan xp-c): which engine runs, or why it is the CPU.
struct ImplicitEngineCheckTests {
    @Test func theCheckNamesTheEngineOrWhyItIsTheCPU() async {
        let text = await ImplicitEngineCheck.run()
        #if canImport(Metal)
        #expect(text.hasPrefix("Metal") || text.hasPrefix("the CPU"))
        #else
        #expect(text.hasPrefix("the CPU") || text.hasPrefix("Vulkan") || text.hasPrefix("Direct3D 12"), "\(text)")
        #endif
    }
}

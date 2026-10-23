/// A solid's HLSL kernel sources (plan xp-c): the prelude, then, for a kernel that calls `sdf`, the two packed buffers, the library and the shape's
/// `sdf`, then the kernel's own buffers and `main`. SDL_GPU compiles one entry point a shader, so where Metal compiles one library a shape, this is one
/// source a kernel; the kernels that do not call `sdf` have the same text for every shape and the pipeline cache makes them once.
enum HLSLKernels {
    static func sources(sdf: String) -> [ImplicitKernel: KernelSource] {
        let shape = HLSLShaderLibrary.withSDF(sdf)
        return [.evaluate: KernelSource(kernel: .evaluate, text: HLSLShaderLibrary.prelude + shape + HLSLShaderLibrary.evaluate)]
    }
}

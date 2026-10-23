/// A solid's HLSL kernel sources (plan xp-c): the prelude, then, for a kernel that calls `sdf`, the two packed buffers, the library and the shape's
/// `sdf`, then the kernel's own buffers and `main`. SDL_GPU compiles one entry point a shader, so where Metal compiles one library a shape, this is one
/// source a kernel; the kernels that do not call `sdf` have the same text for every shape and the pipeline cache makes them once.
enum HLSLKernels {
    static func sources(sdf: String) -> [ImplicitKernel: KernelSource] {
        let prelude = HLSLShaderLibrary.prelude
        let shape = HLSLShaderLibrary.withSDF(sdf)
        let texts: [ImplicitKernel: String] = [
            .evaluate: prelude + shape + HLSLShaderLibrary.evaluate,
            .sample: prelude + shape + HLSLMeshShaderLibrary.sample,
            .place: prelude + shape + HLSLMeshShaderLibrary.place,
            .clear: prelude + HLSLMeshShaderLibrary.clear,
            .classify: prelude + HLSLMeshShaderLibrary.classify,
            .number: prelude + HLSLMeshShaderLibrary.number,
            .emit: prelude + HLSLMeshShaderLibrary.emit,
        ]
        return texts.reduce(into: [:]) { $0[$1.key] = KernelSource(kernel: $1.key, text: $1.value) }
    }
}

#if canImport(Metal)
@preconcurrency import Metal
@testable import CreatorImplicit

/// A Metal compute pipeline as a `ComputePipeline` (test support). `MTLComputePipelineState` is thread-safe.
final class MSLComputePipeline: ComputePipeline, @unchecked Sendable {
    let state: any MTLComputePipelineState
    init(_ state: any MTLComputePipelineState) { self.state = state }
}
#endif

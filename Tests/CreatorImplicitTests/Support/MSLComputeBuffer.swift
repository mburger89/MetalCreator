#if canImport(Metal)
@preconcurrency import Metal
@testable import CreatorImplicit

/// A Metal buffer as a `ComputeBuffer` (test support). `@unchecked`: an `MTLBuffer` may cross threads; the engine touches its contents only between
/// batches it awaited.
final class MSLComputeBuffer: ComputeBuffer, @unchecked Sendable {
    let buffer: any MTLBuffer
    var length: Int { buffer.length }
    init(_ buffer: any MTLBuffer) { self.buffer = buffer }
}
#endif

/// The one uniform block every HLSL kernel reads (`cbuffer Params : register(b0, space2)`, `HLSLShaderLibrary.prelude`): Metal's `count` and
/// `MeshParams`, and where the pool, the pictures and the tables start in the two packed buffers. Sixteen four-byte words.
public struct KernelParameters: Sendable, Equatable {
    public var count: UInt32 = 0
    public var poolBase: UInt32 = 0
    public var imagesBase: UInt32 = 0
    public var tablesBase: UInt32 = 0
    public var firstBrick: UInt32 = 0
    public var brickCount: UInt32 = 0
    public var nx: UInt32 = 0
    public var ny: UInt32 = 0
    public var nz: UInt32 = 0
    public var mask: UInt32 = 0
    public var snap: UInt32 = 0
    public var resolution: Float = 0
    public var firstSlot: UInt32 = 0
    public var padding0: UInt32 = 0
    public var padding1: UInt32 = 0
    public var padding2: UInt32 = 0

    public init() {}

    /// The block as the GPU reads it, from an explicit word list (no reliance on Swift's struct layout).
    var bytes: [UInt8] {
        let words: [UInt32] = [
            count, poolBase, imagesBase, tablesBase, firstBrick, brickCount, nx, ny, nz, mask, snap, resolution.bitPattern,
            firstSlot, padding0, padding1, padding2,
        ]
        return words.withUnsafeBytes { Array($0) }
    }
}

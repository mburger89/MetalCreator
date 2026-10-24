/// One kernel's HLSL text and its digest (plan xp-c): what a backend compiles to a pipeline and what the pipeline cache is keyed by, as Metal's is by
/// `ShapeKey`. The digest is FNV-1a 64 of the UTF-8 text in hex, stable across processes (the offline test compile names its files by it).
public struct KernelSource: Sendable, Hashable {
    public let kernel: ImplicitKernel
    public let text: String
    public let digest: String

    public init(kernel: ImplicitKernel, text: String) {
        self.kernel = kernel
        self.text = text
        digest = Self.fnv1a(text)
    }

    static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    public static func == (lhs: KernelSource, rhs: KernelSource) -> Bool { lhs.digest == rhs.digest && lhs.text == rhs.text }
    public func hash(into hasher: inout Hasher) { hasher.combine(digest) }
}

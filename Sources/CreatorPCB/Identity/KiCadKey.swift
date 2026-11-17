/// The one place an identity string becomes the integer item of a tag (and a platform-independent hash).
public enum KiCadKey {
    /// FNV-1a, 64 bits, over the string's UTF-8 bytes.
    public static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// A negative `Int` of magnitude at most 2^60, which `InstancePath` never reads as a path.
    public static func item(for text: String) -> Int {
        item(forHash: fnv1a64(text))
    }

    static func item(forHash hash: UInt64) -> Int {
        -(Int(hash & 0x0FFF_FFFF_FFFF_FFFF) + 1)
    }
}

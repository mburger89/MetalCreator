import Foundation

/// A strict base64 reader for text that came out of an untrusted file.
public enum Base64 {
    /// Standard alphabet, `=` padding, whitespace ignored; any other byte, misplaced padding or a bad length is `nil`.
    /// `nil` too when the result would exceed `limit` bytes (checked before anything is allocated).
    public static func decode(_ text: Substring.UTF8View, limit: Int) -> Data? {
        guard let symbols = symbols(of: text) else { return nil }
        let size = symbols.count / 4 * 3 + max(0, symbols.count % 4 - 1)
        guard size <= limit else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(size)
        var index = 0
        while index + 4 <= symbols.count {
            let word = UInt32(symbols[index]) << 18 | UInt32(symbols[index + 1]) << 12
                | UInt32(symbols[index + 2]) << 6 | UInt32(symbols[index + 3])
            out.append(UInt8(word >> 16 & 0xFF))
            out.append(UInt8(word >> 8 & 0xFF))
            out.append(UInt8(word & 0xFF))
            index += 4
        }
        let rest = symbols.count - index
        if rest >= 2 { out.append(symbols[index] << 2 | symbols[index + 1] >> 4) }
        if rest == 3 { out.append(symbols[index + 1] << 4 | symbols[index + 2] >> 2) }
        return Data(out)
    }

    /// The six-bit values of the text, or `nil` for a stray byte, misplaced padding or a length that is no base64.
    private static func symbols(of text: Substring.UTF8View) -> [UInt8]? {
        var symbols: [UInt8] = []
        symbols.reserveCapacity(text.count)
        var padding = 0
        for byte in text {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D: continue
            case UInt8(ascii: "="): padding += 1
            default:
                guard padding == 0, let value = value(of: byte) else { return nil }
                symbols.append(value)
            }
        }
        guard padding <= 2, (symbols.count + padding) % 4 == 0, symbols.count % 4 != 1 else { return nil }
        return symbols
    }

    private static func value(of byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): return byte - UInt8(ascii: "A")
        case UInt8(ascii: "a")...UInt8(ascii: "z"): return byte - UInt8(ascii: "a") + 26
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0") + 52
        case UInt8(ascii: "+"): return 62
        case UInt8(ascii: "/"): return 63
        default: return nil
        }
    }
}

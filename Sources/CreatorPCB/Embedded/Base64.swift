import Foundation

/// A strict base64 reader for text that came out of an untrusted file.
public enum Base64 {
    /// Standard alphabet, `=` padding, whitespace ignored; any other byte, misplaced padding or a bad length is `nil`.
    /// `nil` too when the result would exceed `limit` bytes (checked after one counting pass, before anything is allocated).
    public static func decode(_ text: Substring.UTF8View, limit: Int) -> Data? {
        guard let symbolCount = count(text) else { return nil }
        let size = symbolCount / 4 * 3 + max(0, symbolCount % 4 - 1)
        guard size <= limit else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(size)
        var word: UInt32 = 0
        var held = 0
        for byte in text {
            guard let value = value(of: byte) else { continue }
            word = word << 6 | UInt32(value)
            held += 1
            if held == 4 {
                out.append(UInt8(word >> 16 & 0xFF))
                out.append(UInt8(word >> 8 & 0xFF))
                out.append(UInt8(word & 0xFF))
                word = 0
                held = 0
            }
        }
        if held == 2 { out.append(UInt8(word >> 4 & 0xFF)) }
        if held == 3 { out.append(UInt8(word >> 10 & 0xFF)); out.append(UInt8(word >> 2 & 0xFF)) }
        return Data(out)
    }

    /// The number of alphabet symbols, or `nil` for a stray byte, misplaced padding or a length that is no base64.
    private static func count(_ text: Substring.UTF8View) -> Int? {
        var symbols = 0
        var padding = 0
        for byte in text {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D: continue
            case UInt8(ascii: "="): padding += 1
            default:
                guard padding == 0, value(of: byte) != nil else { return nil }
                symbols += 1
            }
        }
        guard padding <= 2, (symbols + padding) % 4 == 0, symbols % 4 != 1 else { return nil }
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

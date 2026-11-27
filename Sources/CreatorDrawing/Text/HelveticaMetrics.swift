import Foundation

/// Helvetica's advance widths and the Windows-1252 ("WinAnsi") mapping the PDF's base-14 font uses (plan R13).
/// The widths are Adobe's Core 14 `Helvetica.afm`, in 1/1000 em, indexed by WinAnsi byte; no kerning.
public enum HelveticaMetrics {
    /// The height of a capital letter in 1/1000 em.
    public static let capHeight = 718

    /// The vertical extent of the glyph "(" and ")" about the baseline in 1/1000 em: Helvetica.afm's `parenleft` and `parenright`
    /// bounding boxes are both `-207` to `733`.
    public static let parenthesisExtent: ClosedRange<Int> = -207...733

    /// How far above the baseline the middle of a parenthesis stands, for lettering of cap height `height`.
    public static func parenthesisMiddle(height: Double) -> Double {
        let size = height * 1000 / Double(capHeight)
        return Double(parenthesisExtent.lowerBound + parenthesisExtent.upperBound) / 2 * size / 1000
    }

    /// The WinAnsi byte for `character`, or `nil` when the font has no such glyph.
    public static func winAnsi(_ character: Character) -> UInt8? {
        let scalars = String(character).precomposedStringWithCanonicalMapping.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return nil }
        let value = scalar.value
        switch value {
        case 0x20...0x7E, 0xA0...0xFF: return UInt8(value)
        default: return specials[value]
        }
    }

    /// The Unicode character a WinAnsi byte stands for, or `nil` for the bytes WinAnsi leaves undefined.
    public static func character(of byte: UInt8) -> Character? {
        switch byte {
        case 0x20...0x7E, 0xA0...0xFF: return Character(Unicode.Scalar(byte))
        default:
            guard let value = specialValues[byte], let scalar = Unicode.Scalar(value) else { return nil }
            return Character(scalar)
        }
    }

    /// The Unicode scalar a WinAnsi byte stands for, or `nil` for the bytes WinAnsi leaves undefined (DR-5 R14: the SVG writes
    /// a run's bytes back as text).
    public static func unicode(forWinAnsi byte: UInt8) -> Unicode.Scalar? {
        character(of: byte)?.unicodeScalars.first
    }

    /// The advance of a WinAnsi byte in 1/1000 em (0 for a byte with no glyph).
    public static func advance(of byte: UInt8) -> Int {
        byte >= 32 ? advances[Int(byte) - 32] : 0
    }

    // Windows-1252's assignments in 0x80...0x9F.
    private static let specialValues: [UInt8: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
        0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018,
        0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC,
        0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    ]

    private static let specials: [UInt32: UInt8] = {
        var result: [UInt32: UInt8] = [:]
        for (byte, value) in specialValues { result[value] = byte }
        return result
    }()

    /// Bytes 32 through 255. The six bytes WinAnsi leaves undefined (0x7F, 0x81, 0x8D, 0x8F, 0x90, 0x9D) hold 0.
    private static let advances: [Int] = [
        // 0x20 to 0x2F
        278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
        // 0x30 to 0x3F
        556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
        // 0x40 to 0x4F
        1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
        // 0x50 to 0x5F
        667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
        // 0x60 to 0x6F
        333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
        // 0x70 to 0x7F
        556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, 0,
        // 0x80 to 0x8F
        556, 0, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 0, 611, 0,
        // 0x90 to 0x9F
        0, 222, 222, 333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 0, 500, 667,
        // 0xA0 to 0xAF
        278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333,
        // 0xB0 to 0xBF
        400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611,
        // 0xC0 to 0xCF
        667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
        // 0xD0 to 0xDF
        722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
        // 0xE0 to 0xEF
        556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278,
        // 0xF0 to 0xFF
        556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500,
    ]
}

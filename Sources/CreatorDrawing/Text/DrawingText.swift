/// A line of lettering laid out in Helvetica (plan R13).
public struct TextRun: Hashable, Sendable {
    /// The WinAnsi bytes, with "?" where a character had no glyph.
    public var bytes: [UInt8]
    /// Each glyph's x from the run's start, in millimetres.
    public var offsets: [Double]
    /// The run's width in millimetres.
    public var width: Double
    public var hasReplacements: Bool
    /// The string drawn: the WinAnsi text, "?" in place of what was replaced.
    public var shown: String

    public init(bytes: [UInt8], offsets: [Double], width: Double, hasReplacements: Bool, shown: String) {
        self.bytes = bytes
        self.offsets = offsets
        self.width = width
        self.hasReplacements = hasReplacements
        self.shown = shown
    }
}

public enum DrawingText {
    /// The smallest height a fitted value shrinks to.
    public static let minimumHeight = 1.8

    /// Lays `text` out with cap height `height` (millimetres).
    public static func layout(_ text: String, height: Double) -> TextRun {
        let unit = height / Double(HelveticaMetrics.capHeight)  // millimetres per 1/1000 em
        var bytes: [UInt8] = []
        var offsets: [Double] = []
        var shown = ""
        var replaced = false
        var x = 0.0
        let questionMark = UInt8(ascii: "?")
        for character in text {
            var byte = HelveticaMetrics.winAnsi(character)
            if let found = byte, HelveticaMetrics.character(of: found) != nil {
                shown.append(HelveticaMetrics.character(of: found) ?? "?")
            } else {
                byte = questionMark
                shown.append("?")
                replaced = true
            }
            let glyph = byte ?? questionMark
            bytes.append(glyph)
            offsets.append(x)
            x += Double(HelveticaMetrics.advance(of: glyph)) * unit
        }
        return TextRun(bytes: bytes, offsets: offsets, width: x, hasReplacements: replaced, shown: shown)
    }

    /// `text` shrunk to fit `width`, never below 1.8 mm, then cut with "…" (plan R13).
    public static func fitted(_ text: String, height: Double, width: Double) -> (run: TextRun, height: Double) {
        let whole = layout(text, height: height)
        if whole.width <= width { return (whole, height) }
        let smaller = Swift.max(minimumHeight, Swift.min(height, height * width / whole.width))
        let shrunk = layout(text, height: smaller)
        if shrunk.width <= width { return (shrunk, smaller) }
        var characters = Array(text)
        while !characters.isEmpty {
            characters.removeLast()
            let cut = layout(String(characters) + "…", height: smaller)
            if cut.width <= width { return (cut, smaller) }
        }
        return (layout("…", height: smaller), smaller)
    }
}

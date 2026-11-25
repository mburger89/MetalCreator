import CreatorGeometry

/// A symbol drawn as strokes inside a label, never a glyph (plan R12).
public enum LabelSymbol: Hashable, Sendable {
    case depth, counterbore, countersink

    var plain: String {
        switch self {
        case .depth: "↧"
        case .counterbore: "⌴"
        case .countersink: "⌵"
        }
    }
}

public enum LabelPiece: Hashable, Sendable {
    case text(String)
    case symbol(LabelSymbol)
}

/// Two small texts one over the other: a deviation or a pair of limits.
public struct StackedText: Hashable, Sendable {
    public var upper: String
    public var lower: String

    public init(upper: String, lower: String) {
        self.upper = upper
        self.lower = lower
    }
}

public enum SizeSymbol: Sendable { case none, radius, diameter }

/// The text of a dimension as pieces (plan R10): the first line, then its stack and trailing text, then further lines below.
public struct DimensionLabel: Hashable, Sendable {
    public var lines: [[LabelPiece]]
    public var stack: StackedText?
    public var trailing: String
    public var isBoxed: Bool
    /// True when made with a non-empty prefix or suffix (R14: its texts carry `plainText` as their original).
    public private(set) var hasTypedText: Bool

    public init(
        lines: [[LabelPiece]], stack: StackedText? = nil, trailing: String = "", isBoxed: Bool = false, hasTypedText: Bool = false
    ) {
        self.lines = lines
        self.stack = stack
        self.trailing = trailing
        self.isBoxed = isBoxed
        self.hasTypedText = hasTypedText
    }

    /// For lists and warnings, never drawn: symbols as ↧ ⌴ ⌵, the stack as "upper/lower".
    public var plainText: String {
        var result: [String] = []
        for (index, line) in lines.enumerated() {
            var text = line.map { piece in
                switch piece {
                case .text(let string): string
                case .symbol(let symbol): symbol.plain
                }
            }.joined()
            if index == 0 {
                if let stack { text += (text.isEmpty ? "" : " ") + stack.upper + "/" + stack.lower }
                if !trailing.isEmpty { text += (text.isEmpty ? "" : " ") + trailing }
            }
            result.append(text)
        }
        return result.joined(separator: "\n")
    }

    /// The label with "?" after the first line's text, before any stack.
    public func lost() -> DimensionLabel {
        var copy = self
        if copy.lines.isEmpty { copy.lines = [[]] }
        if case .text(let last)? = copy.lines[0].last {
            copy.lines[0][copy.lines[0].count - 1] = .text(last + "?")
        } else {
            copy.lines[0].append(.text("?"))
        }
        return copy
    }

    /// Prefix before and suffix after, joined by spaces; the suffix goes after the stack.
    func typed(prefix: String, suffix: String) -> DimensionLabel {
        guard !prefix.isEmpty || !suffix.isEmpty else { return self }
        var copy = self
        copy.hasTypedText = true
        if !prefix.isEmpty {
            if copy.lines.isEmpty { copy.lines = [[]] }
            if case .text(let first)? = copy.lines[0].first {
                copy.lines[0][0] = .text(prefix + " " + first)
            } else {
                copy.lines[0].insert(.text(prefix + " "), at: 0)
            }
        }
        if !suffix.isEmpty { copy.trailing = copy.trailing.isEmpty ? suffix : copy.trailing + " " + suffix }
        return copy
    }

    public static func chamfer(leg: Double, angle: Double, precision: Int?, format: NumberFormat) -> DimensionLabel {
        let size = DimensionNumber.length(leg, precision: precision, format: format)
        if format.standard == .iso, Swift.abs(angle - .pi / 4) <= 1e-9 { return DimensionLabel(lines: [[.text("C" + size)]]) }
        let times = format.standard == .iso ? "×" : "X"
        let degrees = DimensionNumber.angle(angle, precision: nil, format: format)
        return DimensionLabel(lines: [[.text("\(size) \(times) \(degrees)")]])
    }

    /// The origin of an ordinate dimension reads "0"; every other value is a length.
    public static func ordinate(_ mm: Double, precision: Int?, format: NumberFormat) -> DimensionLabel {
        let value = format.units.value(fromMillimetres: mm)
        let places = precision.map(DimensionNumber.clamped) ?? format.units.fractionDigits
        let rendered = DimensionNumber.render(value, places: places, keepZeros: !format.dropsTrailingZeros, format: format)
        return DimensionLabel(lines: [[.text(rendered.isZero ? "0" : rendered.text)]])
    }

    public static func hole(
        _ shape: HoleShape, precision: Int?, prefix: String, suffix: String, format: NumberFormat
    ) -> DimensionLabel {
        func length(_ mm: Double) -> String { DimensionNumber.length(mm, precision: precision, format: format) }
        let times = format.standard == .iso ? "×" : "X"
        var lines: [[LabelPiece]] = []
        if let depth = shape.depth {
            lines.append([.text("Ø\(length(shape.diameter)) "), .symbol(.depth), .text(length(depth))])
        } else {
            lines.append([.text("Ø\(length(shape.diameter)) THRU")])
        }
        if let bore = shape.counterbore {
            lines.append([
                .symbol(.counterbore), .text("Ø\(length(bore.diameter)) "), .symbol(.depth), .text(length(bore.depth)),
            ])
        }
        if let sink = shape.countersink {
            let angle = DimensionNumber.angle(sink.angle, precision: nil, format: format)
            lines.append([.symbol(.countersink), .text("Ø\(length(sink.diameter)) \(times) \(angle)")])
        }
        return DimensionLabel(lines: lines).typed(prefix: prefix, suffix: suffix)
    }
}

extension DocumentUnits {
    /// Reads what a person typed: a plain number in the document's unit, or a number followed by a unit suffix.
    /// Returns millimetres for a length, degrees for an angle, an integer for a count; nil for anything it cannot read
    /// exactly (other separators, fractions, exponents, unknown or wrong-quantity units).
    public func parse(_ text: String, quantity: DimensionQuantity) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (number, rest) = Self.splitNumber(trimmed), let value = Double(number), value.isFinite else {
            return nil
        }
        let suffix = rest.trimmingCharacters(in: .whitespaces).lowercased()
        switch quantity {
        case .length, .radius, .diameter:
            guard let scale = lengthScale(suffix: suffix) else { return nil }
            let result = value * scale
            return result.isFinite ? result : nil
        case .angle:
            return ["", "°", "deg"].contains(suffix) ? value : nil
        case .count:
            return suffix.isEmpty && value == value.rounded() ? value : nil
        }
    }

    /// Millimetres per typed unit; nil when the suffix names no length unit.
    private func lengthScale(suffix: String) -> Double? {
        switch suffix {
        case "": length.millimetresPerUnit
        case "mm": 1
        case "cm": 10
        case "in", "inch", "inches", "\"": 25.4
        default: nil
        }
    }

    /// Splits `[+-]?(digits(.digits?)?|.digits)` from what follows it, as a string `Double` reads.
    private static func splitNumber(_ text: String) -> (number: String, rest: Substring)? {
        var index = text.startIndex
        var number = ""
        if index < text.endIndex, text[index] == "+" || text[index] == "-" {
            number.append(text[index])
            index = text.index(after: index)
        }
        func takeDigits() -> Int {
            var count = 0
            while index < text.endIndex, text[index].isASCII, text[index].isNumber {
                number.append(text[index])
                index = text.index(after: index)
                count += 1
            }
            return count
        }
        var digits = takeDigits()
        if index < text.endIndex, text[index] == "." {
            number.append(".")
            index = text.index(after: index)
            let fraction = takeDigits()
            if digits == 0, fraction == 0 { return nil }
            if fraction == 0 { number.append("0") }
            if digits == 0 { number.insert("0", at: number.index(number.endIndex, offsetBy: -fraction - 1)) }
            digits += fraction
        }
        guard digits > 0 else { return nil }
        return (number, text[index...])
    }
}

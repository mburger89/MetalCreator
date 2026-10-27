import CreatorGeometry

extension DimensionStyle {
    /// The text of a dimension: the number by quantity, then "R"/"Ø", then "NX ", then "name = ", then
    /// parentheses for a reference. Millimetres keep the leading zero and drop trailing zeros; inches drop the
    /// leading zero below 1 and keep trailing zeros to the precision.
    public func text(_ reading: DimensionReading, units: DocumentUnits) -> String {
        var text = number(reading, units: units)
        switch reading.quantity {
        case .radius: text = "R" + text
        case .diameter: text = "\u{D8}" + text
        case .length, .angle, .count: break
        }
        if let count = reading.count, count >= 2 { text = "\(count)X " + text }
        if let name = reading.name { text = name + " = " + text }
        return reading.isReference ? "(" + text + ")" : text
    }

    private func number(_ reading: DimensionReading, units: DocumentUnits) -> String {
        switch reading.quantity {
        case .length, .radius, .diameter:
            let shown = units.value(fromMillimetres: reading.value)
            if units.length == .inches {
                let digits = units.fractionDigits
                return Self.droppingLeadingZero(DocumentUnits.number(shown, minimum: digits, maximum: digits))
            }
            return DocumentUnits.number(shown, minimum: 0, maximum: units.fractionDigits)
        case .angle:
            return DocumentUnits.number(reading.value, minimum: 0, maximum: 1) + "°"
        case .count:
            return DocumentUnits.number(reading.value, minimum: 0, maximum: 0) + "X"
        }
    }

    /// "0.50" becomes ".50" and "-0.50" becomes "-.50"; "0" and "10.5" stay.
    private static func droppingLeadingZero(_ text: String) -> String {
        if text.hasPrefix("0.") { return String(text.dropFirst()) }
        if text.hasPrefix("-0.") { return "-" + text.dropFirst(2) }
        return text
    }
}

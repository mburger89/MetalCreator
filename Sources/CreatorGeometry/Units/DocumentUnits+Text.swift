import Foundation

extension DocumentUnits {
    /// The suffix a field shows after the number.
    public func suffix(for quantity: DimensionQuantity) -> String {
        switch quantity {
        case .length, .radius, .diameter: " " + length.symbol
        case .angle: "°"
        case .count: ""
        }
    }

    /// The text a value box opens with: enough decimals (4, or 5 in inches) that opening it and pressing Return
    /// changes nothing, trailing zeros dropped, no suffix.
    public func editText(_ value: Double, quantity: DimensionQuantity) -> String {
        switch quantity {
        case .length, .radius, .diameter:
            let digits = length == .inches ? 5 : 4
            return Self.number(self.value(fromMillimetres: value), minimum: 0, maximum: digits)
        case .angle:
            return Self.number(value, minimum: 0, maximum: 4)
        case .count:
            return Self.number(value, minimum: 0, maximum: 0)
        }
    }

    /// The text of a read-only field: rounded to the precision, with its unit. Millimetres drop trailing zeros,
    /// inches keep them; an angle shows at most one decimal.
    public func fieldText(_ value: Double, quantity: DimensionQuantity) -> String {
        let number: String
        switch quantity {
        case .length, .radius, .diameter:
            let shown = self.value(fromMillimetres: value)
            number = length == .inches
                ? Self.number(shown, minimum: fractionDigits, maximum: fractionDigits)
                : Self.number(shown, minimum: 0, maximum: fractionDigits)
        case .angle:
            number = Self.number(value, minimum: 0, maximum: 1)
        case .count:
            number = Self.number(value, minimum: 0, maximum: 0)
        }
        return number + suffix(for: quantity)
    }

    /// A length from millimetres with exactly the precision's digits and no unit, as the readout shows it.
    public func readoutNumber(_ millimetres: Double) -> String {
        Self.number(value(fromMillimetres: millimetres), minimum: fractionDigits, maximum: fractionDigits)
    }

    /// A locale-independent number with `minimum...maximum` decimals, rounded half away from zero, never "-0".
    static func number(_ value: Double, minimum: Int, maximum: Int) -> String {
        let style = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US_POSIX"))
            .grouping(.never)
            .rounded(rule: .toNearestOrAwayFromZero)
            .precision(.fractionLength(minimum...maximum))
        let text = value.formatted(style)
        guard text.hasPrefix("-"), text.allSatisfy({ $0 == "-" || $0 == "0" || $0 == "." }) else { return text }
        return String(text.dropFirst())
    }
}

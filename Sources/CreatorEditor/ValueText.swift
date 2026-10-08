import CreatorGraph
import Foundation

/// How numbers are shown and typed in node rows and the inspector.
public enum ValueText {
    /// One fixed locale for showing numbers, so a machine set to "0,25" still shows "0.25",
    /// which `parse` reads back. Localised entry is deferred with string localisation.
    public static let locale = Locale(identifier: "en_US_POSIX")

    /// "60 mm", "45°", "3", "0.25": up to three decimals, with the unit.
    public static func format(_ value: Double, unit: ValueUnit) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(locale))
        switch unit {
        case .millimetres: return "\(number) mm"
        case .degrees: return "\(number)°"
        case .count, .none: return number
        }
    }

    /// The constant shown on an unwired input's row. Covers every kind M3 ships, including the
    /// `.edgePicks` setting ("2 picks"). Written with `if case`, so a kind added after M3 still
    /// compiles and shows "—".
    public static func format(_ value: ConstantValue?, unit: ValueUnit) -> String {
        if case .number(let number)? = value { return format(number, unit: unit) }
        if case .integer(let integer)? = value { return format(Double(integer), unit: unit) }
        if case .bool(let flag)? = value { return flag ? "On" : "Off" }
        if case .vector(let v)? = value { return "\(format(v.x, unit: unit)), \(format(v.y, unit: unit)), \(format(v.z, unit: unit))" }
        if case .plane(let plane)? = value { return PlaneChoice(plane)?.rawValue ?? "Custom plane" }
        if case .text(let text)? = value { return text }
        if case .edgePicks(let picks)? = value { return picks.count == 1 ? "1 pick" : "\(picks.count) picks" }
        return "—"
    }

    /// A typed number, ignoring spaces and a trailing unit ("12.5 mm", "45°"); `nil` if it isn't one.
    public static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let number = trimmed.prefix { "0123456789.-+eE".contains($0) }
        guard !number.isEmpty, let value = Double(String(number)), value.isFinite else { return nil }
        let rest = trimmed.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        return ["", "mm", "°", "deg"].contains(rest) ? value : nil
    }

    /// A typed number as a whole number, rounded; `nil` when no `Int` holds it ("1e300").
    /// `Int(_:)` would trap there, so this uses `Int(exactly:)`.
    public static func wholeNumber(_ value: Double) -> Int? {
        Int(exactly: value.rounded())
    }
}

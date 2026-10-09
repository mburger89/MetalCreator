import CreatorSketch
import Foundation

/// A dimension's value as the inspector shows and reads it: up to three decimals, in millimetres or degrees.
enum DimensionText {
    static let locale = Locale(identifier: "en_US_POSIX")

    /// "12.5 mm", "30°".
    static func format(_ value: Double, kind: DimensionKind) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(locale))
        if case .angle = kind { return "\(number)°" }
        return "\(number) mm"
    }

    /// A typed value, ignoring spaces and a trailing unit ("12.5 mm", "45°"); `nil` if it isn't a finite number.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let number = trimmed.prefix { "0123456789.-+eE".contains($0) }
        guard !number.isEmpty, let value = Double(String(number)), value.isFinite else { return nil }
        let rest = trimmed.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        return ["", "mm", "°", "deg"].contains(rest) ? value : nil
    }
}

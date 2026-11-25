import Foundation

/// Values the title block shows that come from the model, not the sheet.
public struct TitleBlockFacts: Hashable, Sendable {
    /// The mass text, or `nil` when the field stays empty (plan R16).
    public var massText: String?

    public init(massText: String? = nil) {
        self.massText = massText
    }

    /// "8.4 g" under 10 g, "84 g" under 1000 g, "1.234 kg" above, or pounds ("2.721 lb") when `inches`.
    public static func massText(grams: Double, inches: Bool) -> String {
        if inches { return String(format: "%.3f lb", grams / 453.59237) }
        if grams < 10 { return String(format: "%.1f g", grams) }
        if grams < 1000 { return String(format: "%.0f g", grams) }
        return String(format: "%.3f kg", grams / 1000)
    }
}

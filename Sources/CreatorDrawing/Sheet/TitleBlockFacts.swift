import CreatorKernel
import Foundation

/// The title block's logo as the composer is given it (DR-5 R11): decoded grey pixels, or why it could not be.
public enum LogoFact: Hashable, Sendable {
    case picture(GreyPixels)
    case unreadable(String)
}

/// Values the title block shows that come from the model, not the sheet.
public struct TitleBlockFacts: Hashable, Sendable {
    /// The mass text, or `nil` when the field stays empty (plan R16).
    public var massText: String?
    /// Every part the drawing wants, by Output: its name, quantity and whether it is removed (DR-5 R5). Read by lookup only.
    public var parts: [NodeID: PartFacts]
    /// The logo of the sheet's title block, `nil` with none (DR-5 R11).
    public var logo: LogoFact?

    public init(massText: String? = nil, parts: [NodeID: PartFacts] = [:], logo: LogoFact? = nil) {
        self.logo = logo
        self.massText = massText
        self.parts = parts
    }

    /// "8.4 g" under 10 g, "84 g" under 1000 g, "1.234 kg" above, or pounds ("2.721 lb") when `inches`.
    public static func massText(grams: Double, inches: Bool) -> String {
        if inches { return String(format: "%.3f lb", grams / 453.59237) }
        // Round first, then choose the form, so a value that rounds up to a boundary takes the form the boundary has.
        let tenths = (grams * 10).rounded() / 10
        if tenths < 10 { return String(format: "%.1f g", tenths) }
        let whole = grams.rounded()
        if whole < 1000 { return String(format: "%.0f g", whole) }
        return String(format: "%.3f kg", grams / 1000)
    }
}

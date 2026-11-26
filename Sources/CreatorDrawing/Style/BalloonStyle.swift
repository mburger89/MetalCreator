/// A balloon's sizes as factors of the notes' text height h (DR-5 R4): ISO 6433's item reference and ASME Y14.34's balloon share one form.
public struct BalloonStyle: Hashable, Sendable {
    /// The number's cap height over h.
    public let text: Double
    /// The circle's least radius over h.
    public let radius: Double
    /// The gap between the number and the circle over h.
    public let padding: Double

    public static let standard = BalloonStyle(text: 2, radius: 2, padding: 0.5)

    public static func of(_ standard: DrawingStandard) -> BalloonStyle { Self.standard }
}

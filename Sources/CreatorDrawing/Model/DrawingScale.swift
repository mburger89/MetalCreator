/// A ratio of drawing to model (plan R8), such as 1 : 2.
public struct DrawingScale: Hashable, Sendable, Codable {
    public var numerator: Int
    public var denominator: Int

    public init(numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public var value: Double { Double(numerator) / Double(denominator) }

    /// Each side is a whole number from 1 to 1000.
    public var isValid: Bool { (1...1000).contains(numerator) && (1...1000).contains(denominator) }

    /// ISO 5455's preferred scales, largest first.
    public static let preferred: [DrawingScale] = [
        (50, 1), (20, 1), (10, 1), (5, 1), (2, 1), (1, 1), (1, 2), (1, 5), (1, 10), (1, 20), (1, 50), (1, 100), (1, 200),
        (1, 500), (1, 1000),
    ].map { DrawingScale(numerator: $0.0, denominator: $0.1) }

    /// "1 : 2" in ISO, "1:2" in ASME.
    public func text(for standard: DrawingStandard) -> String {
        standard == .iso ? "\(numerator) : \(denominator)" : "\(numerator):\(denominator)"
    }
}

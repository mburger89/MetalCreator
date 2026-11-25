/// The drafting standard a drawing follows (ISO or ASME), which sets its projection angle, lettering and line weights.
public enum DrawingStandard: String, Sendable, Codable, CaseIterable {
    case iso
    case asme

    /// ISO projects in first angle, ASME in third.
    public var isFirstAngle: Bool { self == .iso }
}

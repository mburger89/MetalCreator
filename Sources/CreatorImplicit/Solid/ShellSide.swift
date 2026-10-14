/// Which side of the surface a Shell's wall lies on (implicit spec §3.3).
public enum ShellSide: Int, Hashable, Sendable, CaseIterable {
    /// The wall is inside the surface (the solid keeps its outline).
    case inward = 0
    /// The wall is outside the surface.
    case outward = 1
    /// The wall is centred on the surface.
    case centred = 2

    /// The names the Shell node's segmented control shows, in raw-value order.
    public static let options = ["Inward", "Outward", "Centred"]

    /// The wall's centre line as a signed distance from the surface: the wall is the points within half the thickness of it.
    /// Negative is inside.
    public func centreOffset(thickness: Double) -> Double {
        switch self {
        case .inward: -thickness / 2
        case .outward: thickness / 2
        case .centred: 0
        }
    }

    public var name: String { Self.options[rawValue] }
}

import CreatorGeometry

/// The inspector's plane picker choices (spec §7.1: XY, XZ or YZ).
public enum PlaneChoice: String, CaseIterable, Sendable {
    case xy = "XY", xz = "XZ", yz = "YZ"

    public var plane: Plane {
        switch self {
        case .xy: .xy
        case .xz: .xz
        case .yz: .yz
        }
    }

    /// The choice whose orientation matches `plane` (its origin may be offset), if any.
    public init?(_ plane: Plane) {
        guard let match = Self.allCases.first(where: { $0.plane.normal == plane.normal && $0.plane.xAxis == plane.xAxis }) else {
            return nil
        }
        self = match
    }
}

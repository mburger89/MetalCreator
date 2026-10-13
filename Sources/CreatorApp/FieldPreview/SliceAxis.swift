import CreatorGeometry

/// One of the three axis planes the slice can lie in (fields spec §6): the legend's XY, YZ and XZ buttons.
enum SliceAxis: CaseIterable, Equatable, Sendable {
    case xy
    case yz
    case xz

    var title: String {
        switch self {
        case .xy: "XY"
        case .yz: "YZ"
        case .xz: "XZ"
        }
    }

    /// The plane through the origin.
    var plane: Plane {
        switch self {
        case .xy: .xy
        case .yz: .yz
        case .xz: .xz
        }
    }
}

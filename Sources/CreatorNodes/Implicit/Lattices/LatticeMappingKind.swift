/// The `mapping` setting of the three lattice nodes (implicit spec §3.5): how the cells are laid on the region. The raw value is what
/// the segmented control stores, so a file saved before 7c-4, which has no `mapping`, reads 0: Straight.
enum LatticeMappingKind: Int, CaseIterable {
    case straight = 0
    case cylindrical = 1
    case spherical = 2
    case face = 3

    /// The names the segmented control shows, in raw-value order.
    static let options = ["Straight", "Cylindrical", "Spherical", "Face"]

    /// The line of help under the mapping's inputs.
    var help: String {
        switch self {
        case .straight:
            "The cells follow the world axes."
        case .cylindrical:
            "The cells wrap round “axis”, the plane's normal through its origin: their angle times the region's mean radius, their "
                + "height along the axis and their distance from it. A whole number of cells goes round. Within 1 mm of the axis the "
                + "lattice is left solid."
        case .spherical:
            "The cells wrap round “centre”, with the polar axis along Z: longitude and latitude times the region's mean radius, and "
                + "the distance from the centre. A whole number of cells goes round the equator. Within 1 mm of the polar axis the "
                + "lattice is left solid."
        case .face:
            "The cells follow the picked face: its two surface directions in millimetres and the depth below it. Pick the face with "
                + "“Pick Face in View…”, on the solid the region was made from. Where the face curves tightly the lattice is left solid."
        }
    }
}

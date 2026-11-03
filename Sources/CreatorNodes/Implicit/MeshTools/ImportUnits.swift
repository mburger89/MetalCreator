/// The length unit an imported mesh is read in (mesh import spec, the node): the file's own where it names one (3MF), else
/// millimetres, or a unit the person says the numbers are in.
enum ImportUnits: Int, CaseIterable {
    case fromFile = 0, millimetres, centimetres, metres, inches

    /// The names the segmented control shows, in raw-value order.
    static let options = ["From file", "mm", "cm", "m", "in"]

    /// Millimetres per unit, or `nil` for the file's own.
    var millimetres: Double? {
        switch self {
        case .fromFile: nil
        case .millimetres: 1
        case .centimetres: 10
        case .metres: 1000
        case .inches: 25.4
        }
    }
}

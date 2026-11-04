/// What Convert Units converts: a quantity and, for each, the units it knows. The factors are exact.
enum ConversionQuantity: Int, CaseIterable {
    case length, angle

    static let options = ["Length", "Angle"]
}

/// A length unit by option index, with its size in millimetres.
enum ConversionLength: Int, CaseIterable {
    case millimetres, centimetres, metres, inches, feet

    static let options = ["mm", "cm", "m", "in", "ft"]

    var millimetres: Double {
        switch self {
        case .millimetres: 1
        case .centimetres: 10
        case .metres: 1000
        case .inches: 25.4
        case .feet: 304.8
        }
    }
}

/// An angle unit by option index, with its size in radians.
enum ConversionAngle: Int, CaseIterable {
    case degrees, radians

    static let options = ["deg", "rad"]

    var radians: Double {
        switch self {
        case .degrees: Double.pi / 180
        case .radians: 1
        }
    }
}

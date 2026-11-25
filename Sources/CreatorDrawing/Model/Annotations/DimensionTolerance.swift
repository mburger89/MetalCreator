// ISO 286 names a hole's deviation with a capital letter.
// swiftlint:disable identifier_name
public enum HoleFitLetter: String, CaseIterable, Codable, Sendable {
    case F, G, H, JS, K, N, P
}
// swiftlint:enable identifier_name

public enum ShaftFitLetter: String, CaseIterable, Codable, Sendable {
    case f, g, h, js, k, n, p, s
}

/// An ISO 286 fit: a hole's capital letter or a shaft's small one, with an IT grade.
public enum FitDesignation: Hashable, Sendable {
    case hole(HoleFitLetter, grade: Int)
    case shaft(ShaftFitLetter, grade: Int)

    /// "H7", "js6".
    public var text: String {
        switch self {
        case .hole(let letter, let grade): "\(letter.rawValue)\(grade)"
        case .shaft(let letter, let grade): "\(letter.rawValue)\(grade)"
        }
    }

    public var grade: Int {
        switch self {
        case .hole(_, let grade), .shaft(_, let grade): grade
        }
    }

    public static let grades = 5...11
}

extension FitDesignation: Codable {
    private enum CodingKeys: String, CodingKey { case type, letter, grade }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let grade = try c.decode(Int.self, forKey: .grade)
        guard Self.grades.contains(grade) else {
            throw DecodingError.dataCorruptedError(forKey: .grade, in: c, debugDescription: "A fit grade is IT5 to IT11.")
        }
        switch try c.decode(String.self, forKey: .type) {
        case "hole": self = .hole(try c.decode(HoleFitLetter.self, forKey: .letter), grade: grade)
        case "shaft": self = .shaft(try c.decode(ShaftFitLetter.self, forKey: .letter), grade: grade)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown fit type.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hole(let letter, let grade):
            try c.encode("hole", forKey: .type)
            try c.encode(letter, forKey: .letter)
            try c.encode(grade, forKey: .grade)
        case .shaft(let letter, let grade):
            try c.encode("shaft", forKey: .type)
            try c.encode(letter, forKey: .letter)
            try c.encode(grade, forKey: .grade)
        }
    }
}

/// A dimension's tolerance (plan R10); values are millimetres, or radians for an angle.
public enum DimensionTolerance: Hashable, Sendable {
    case general
    case symmetric(Double)
    case deviation(upper: Double, lower: Double)
    case limits(upper: Double, lower: Double)
    case reference
    case basic
    case fit(FitDesignation, showsDeviations: Bool)
}

extension DimensionTolerance: Codable {
    private enum CodingKeys: String, CodingKey { case type, value, upper, lower, designation, showsDeviations }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "symmetric": self = .symmetric(try c.decode(Double.self, forKey: .value))
        case "deviation":
            self = .deviation(upper: try c.decode(Double.self, forKey: .upper), lower: try c.decode(Double.self, forKey: .lower))
        case "limits":
            self = .limits(upper: try c.decode(Double.self, forKey: .upper), lower: try c.decode(Double.self, forKey: .lower))
        case "reference": self = .reference
        case "basic": self = .basic
        case "fit":
            // A grade outside IT5 to IT11 makes the designation undecodable: the dimension falls back to the general tolerance.
            if let designation = try? c.decode(FitDesignation.self, forKey: .designation) {
                self = .fit(designation, showsDeviations: try c.decodeIfPresent(Bool.self, forKey: .showsDeviations) ?? true)
            } else {
                self = .general
            }
        default: self = .general
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .general: try c.encode("general", forKey: .type)
        case .symmetric(let value):
            try c.encode("symmetric", forKey: .type)
            try c.encode(value, forKey: .value)
        case .deviation(let upper, let lower):
            try c.encode("deviation", forKey: .type)
            try c.encode(upper, forKey: .upper)
            try c.encode(lower, forKey: .lower)
        case .limits(let upper, let lower):
            try c.encode("limits", forKey: .type)
            try c.encode(upper, forKey: .upper)
            try c.encode(lower, forKey: .lower)
        case .reference: try c.encode("reference", forKey: .type)
        case .basic: try c.encode("basic", forKey: .type)
        case .fit(let designation, let shows):
            try c.encode("fit", forKey: .type)
            try c.encode(designation, forKey: .designation)
            try c.encode(shows, forKey: .showsDeviations)
        }
    }
}

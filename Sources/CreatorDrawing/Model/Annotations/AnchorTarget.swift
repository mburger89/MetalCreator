import CreatorGeometry
import CreatorKernel

/// What an annotation is attached to (plan R3).
public enum AnchorTarget: Hashable, Sendable {
    case edge(EdgePick)
    case corner(EdgePick, EdgePick)
    case centre(EdgePick)
    case outline(FacePick, side: Vector2)
    case axis(FacePick)
    case point(Vector2)

    public var caseName: String {
        switch self {
        case .edge: "edge"
        case .corner: "corner"
        case .centre: "centre"
        case .outline: "outline"
        case .axis: "axis"
        case .point: "point"
        }
    }
}

extension AnchorTarget: Codable {
    private enum CodingKeys: String, CodingKey { case type, pick, first, second, face, side, point }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "edge": self = .edge(try c.decode(EdgePick.self, forKey: .pick))
        case "corner": self = .corner(try c.decode(EdgePick.self, forKey: .first), try c.decode(EdgePick.self, forKey: .second))
        case "centre": self = .centre(try c.decode(EdgePick.self, forKey: .pick))
        case "outline": self = .outline(try c.decode(FacePick.self, forKey: .face), side: try c.decode(Vector2.self, forKey: .side))
        case "axis": self = .axis(try c.decode(FacePick.self, forKey: .face))
        case "point": self = .point(try c.decode(Vector2.self, forKey: .point))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown anchor type.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(caseName, forKey: .type)
        switch self {
        case .edge(let pick), .centre(let pick): try c.encode(pick, forKey: .pick)
        case .corner(let first, let second):
            try c.encode(first, forKey: .first)
            try c.encode(second, forKey: .second)
        case .outline(let face, let side):
            try c.encode(face, forKey: .face)
            try c.encode(side, forKey: .side)
        case .axis(let face): try c.encode(face, forKey: .face)
        case .point(let point): try c.encode(point, forKey: .point)
        }
    }
}

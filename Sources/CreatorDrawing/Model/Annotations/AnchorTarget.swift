import CreatorGeometry
import CreatorKernel

/// What an annotation is attached to (plan R3).
public indirect enum AnchorTarget: Hashable, Sendable {
    case edge(EdgePick)
    case corner(EdgePick, EdgePick)
    case centre(EdgePick)
    case outline(FacePick, side: Vector2)
    case axis(FacePick)
    case point(Vector2)
    /// A target on one part of an assembly view (DR-5 R3); never nested, and never around a point.
    case onPart(NodeID, AnchorTarget)

    public var caseName: String {
        switch self {
        case .edge: "edge"
        case .corner: "corner"
        case .centre: "centre"
        case .outline: "outline"
        case .axis: "axis"
        case .point: "point"
        case .onPart: "onPart"
        }
    }

    /// The part a wrapped target names.
    public var part: NodeID? {
        if case .onPart(let part, _) = self { return part }
        return nil
    }

    /// The target without its part wrapper.
    public var unwrapped: AnchorTarget {
        if case .onPart(_, let target) = self { return target }
        return self
    }
}

extension AnchorTarget: Codable {
    private enum CodingKeys: String, CodingKey { case type, pick, first, second, face, side, point, part, target }

    // swiftlint:disable:next cyclomatic_complexity
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "edge": self = .edge(try c.decode(EdgePick.self, forKey: .pick))
        case "corner": self = .corner(try c.decode(EdgePick.self, forKey: .first), try c.decode(EdgePick.self, forKey: .second))
        case "centre": self = .centre(try c.decode(EdgePick.self, forKey: .pick))
        case "outline": self = .outline(try c.decode(FacePick.self, forKey: .face), side: try c.decode(Vector2.self, forKey: .side))
        case "axis": self = .axis(try c.decode(FacePick.self, forKey: .face))
        case "point": self = .point(try c.decode(Vector2.self, forKey: .point))
        case "onPart":
            // Nesting flattens to the innermost part, and a point has no part (DR-5 R3).
            let part = try c.decode(NodeID.self, forKey: .part)
            switch try c.decode(AnchorTarget.self, forKey: .target) {
            case .onPart(let inner, let target): self = .onPart(inner, target)
            case .point(let point): self = .point(point)
            case let target: self = .onPart(part, target)
            }
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
        case .onPart(let part, let target):
            try c.encode(part, forKey: .part)
            try c.encode(target, forKey: .target)
        }
    }
}

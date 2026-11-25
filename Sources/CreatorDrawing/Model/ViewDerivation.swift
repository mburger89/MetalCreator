import CreatorGeometry
import CreatorKernel

/// A section view's cutting line on its parent (DR-3 R2).
public struct SectionLine: Hashable, Sendable, Codable {
    public var parent: ViewID
    public var cutter: SectionCutter

    public init(parent: ViewID, cutter: SectionCutter) {
        self.parent = parent
        self.cutter = cutter
    }
}

/// A detail view's circle on its parent, in the parent's model plane (R8).
public struct DetailCircle: Hashable, Sendable, Codable {
    public var parent: ViewID
    public var center: Vector2
    public var radius: Double

    public init(parent: ViewID, center: Vector2, radius: Double) {
        self.parent = parent
        self.center = center
        self.radius = radius
    }
}

/// An auxiliary view's arrow: where it was picked on the parent and the way it looks (R9).
public struct AuxiliaryArrow: Hashable, Sendable, Codable {
    public var parent: ViewID
    public var parentFrame: ProjectionFrame
    public var at: Vector2
    public var viewing: Vector2

    public init(parent: ViewID, parentFrame: ProjectionFrame, at: Vector2, viewing: Vector2) {
        self.parent = parent
        self.parentFrame = parentFrame
        self.at = at
        self.viewing = viewing
    }
}

/// What a section, detail or auxiliary view was made from. Coded as `{"type": ..., "data": {...}}`.
public enum ViewDerivation: Hashable, Sendable, Codable {
    case section(SectionLine)
    case detail(DetailCircle)
    case auxiliary(AuxiliaryArrow)

    public var parent: ViewID {
        switch self {
        case .section(let line): line.parent
        case .detail(let circle): circle.parent
        case .auxiliary(let arrow): arrow.parent
        }
    }

    public func withParent(_ parent: ViewID) -> ViewDerivation {
        switch self {
        case .section(var line):
            line.parent = parent
            return .section(line)
        case .detail(var circle):
            circle.parent = parent
            return .detail(circle)
        case .auxiliary(var arrow):
            arrow.parent = parent
            return .auxiliary(arrow)
        }
    }

    /// Whether this is the derivation a view of `kind` carries.
    func matches(_ kind: ViewKind) -> Bool {
        switch self {
        case .section: kind == .section
        case .detail: kind == .detail
        case .auxiliary: kind == .auxiliary
        }
    }

    private enum CodingKeys: String, CodingKey { case type, data }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "section": self = .section(try c.decode(SectionLine.self, forKey: .data))
        case "detail": self = .detail(try c.decode(DetailCircle.self, forKey: .data))
        case "auxiliary": self = .auxiliary(try c.decode(AuxiliaryArrow.self, forKey: .data))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown view derivation.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .section(let line):
            try c.encode("section", forKey: .type)
            try c.encode(line, forKey: .data)
        case .detail(let circle):
            try c.encode("detail", forKey: .type)
            try c.encode(circle, forKey: .data)
        case .auxiliary(let arrow):
            try c.encode("auxiliary", forKey: .type)
            try c.encode(arrow, forKey: .data)
        }
    }
}

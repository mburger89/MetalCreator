public enum LinearDirection: String, Codable, Sendable {
    case horizontal, vertical, aligned
}

public enum OrdinateAxis: String, Codable, Sendable {
    case horizontal, vertical
}

public enum DrawingDimensionKind: Hashable, Sendable {
    case linear(LinearDirection)
    case baseline(LinearDirection)
    case chain(LinearDirection)
    case ordinate(OrdinateAxis)
    case radius, diameter, angle, chamfer
}

/// Where a dimension sits relative to what it measures, in sheet millimetres and radians (plan R7).
public struct DimensionPlacement: Hashable, Codable, Sendable {
    public var offset: Double
    public var angle: Double
    public var textShift: Double?

    public init(offset: Double, angle: Double, textShift: Double? = nil) {
        self.offset = offset
        self.angle = angle
        self.textShift = textShift
    }
}

public struct DrawingDimension: Hashable, Codable, Sendable {
    public var kind: DrawingDimensionKind
    public var anchors: [AnchorTarget]
    public var placement: DimensionPlacement
    public var tolerance: DimensionTolerance
    public var precision: Int?
    public var prefix: String
    public var suffix: String

    public init(
        kind: DrawingDimensionKind, anchors: [AnchorTarget], placement: DimensionPlacement,
        tolerance: DimensionTolerance = .general, precision: Int? = nil, prefix: String = "", suffix: String = ""
    ) {
        self.kind = kind
        self.anchors = anchors
        self.placement = placement
        self.tolerance = tolerance
        self.precision = precision
        self.prefix = prefix
        self.suffix = suffix
    }

    private enum CodingKeys: String, CodingKey { case kind, anchors, placement, tolerance, precision, prefix, suffix }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(DrawingDimensionKind.self, forKey: .kind)
        anchors = try c.decode([AnchorTarget].self, forKey: .anchors)
        placement = try c.decode(DimensionPlacement.self, forKey: .placement)
        tolerance = try c.decodeIfPresent(DimensionTolerance.self, forKey: .tolerance) ?? .general
        precision = try c.decodeIfPresent(Int.self, forKey: .precision)
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        suffix = try c.decodeIfPresent(String.self, forKey: .suffix) ?? ""
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(anchors, forKey: .anchors)
        try c.encode(placement, forKey: .placement)
        if tolerance != .general { try c.encode(tolerance, forKey: .tolerance) }
        try c.encodeIfPresent(precision, forKey: .precision)
        if !prefix.isEmpty { try c.encode(prefix, forKey: .prefix) }
        if !suffix.isEmpty { try c.encode(suffix, forKey: .suffix) }
    }
}

extension DrawingDimensionKind: Codable {
    private enum CodingKeys: String, CodingKey { case type, direction, axis }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "linear": self = .linear(try c.decode(LinearDirection.self, forKey: .direction))
        case "baseline": self = .baseline(try c.decode(LinearDirection.self, forKey: .direction))
        case "chain": self = .chain(try c.decode(LinearDirection.self, forKey: .direction))
        case "ordinate": self = .ordinate(try c.decode(OrdinateAxis.self, forKey: .axis))
        case "radius": self = .radius
        case "diameter": self = .diameter
        case "angle": self = .angle
        case "chamfer": self = .chamfer
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown dimension kind.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .linear(let direction):
            try c.encode("linear", forKey: .type)
            try c.encode(direction, forKey: .direction)
        case .baseline(let direction):
            try c.encode("baseline", forKey: .type)
            try c.encode(direction, forKey: .direction)
        case .chain(let direction):
            try c.encode("chain", forKey: .type)
            try c.encode(direction, forKey: .direction)
        case .ordinate(let axis):
            try c.encode("ordinate", forKey: .type)
            try c.encode(axis, forKey: .axis)
        case .radius: try c.encode("radius", forKey: .type)
        case .diameter: try c.encode("diameter", forKey: .type)
        case .angle: try c.encode("angle", forKey: .type)
        case .chamfer: try c.encode("chamfer", forKey: .type)
        }
    }
}

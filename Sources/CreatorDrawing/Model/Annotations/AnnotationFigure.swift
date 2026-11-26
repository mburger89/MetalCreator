import CreatorGeometry

/// What an annotation drew, in model-plane millimetres: the figure a lost annotation is drawn from (plan R15).
public enum AnnotationFigure: Hashable, Sendable {
    case linear(points: [Vector2], direction: Vector2)
    case ordinate(origin: Vector2, points: [Vector2], direction: Vector2)
    case radial(center: Vector2, radius: Double, isDiameter: Bool)
    case angle(vertex: Vector2, first: [Vector2], second: [Vector2])
    case chamfer(start: Vector2, end: Vector2)
    case hole(center: Vector2, radius: Double)
    case centreMark(center: Vector2, radius: Double)
    case centreLine(start: Vector2, end: Vector2)
    case leaders([Vector2])
    /// A symbol on a line: its foot, the line's unit tangent there and, for a straight edge, the edge's two projected ends (so a
    /// lost datum beyond its edge keeps its extension line); `ends` is empty for a circle or an outline.
    case attachment(foot: Vector2, along: Vector2, ends: [Vector2])
}

extension AnnotationFigure: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, points, direction, origin, center, radius, isDiameter, vertex, first, second, start, end, foot, along, ends
    }

    // swiftlint:disable:next cyclomatic_complexity
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "linear":
            self = .linear(points: try c.decode([Vector2].self, forKey: .points), direction: try c.decode(Vector2.self, forKey: .direction))
        case "ordinate":
            self = .ordinate(
                origin: try c.decode(Vector2.self, forKey: .origin), points: try c.decode([Vector2].self, forKey: .points),
                direction: try c.decode(Vector2.self, forKey: .direction))
        case "radial":
            self = .radial(
                center: try c.decode(Vector2.self, forKey: .center), radius: try c.decode(Double.self, forKey: .radius),
                isDiameter: try c.decode(Bool.self, forKey: .isDiameter))
        case "angle":
            self = .angle(
                vertex: try c.decode(Vector2.self, forKey: .vertex), first: try c.decode([Vector2].self, forKey: .first),
                second: try c.decode([Vector2].self, forKey: .second))
        case "chamfer":
            self = .chamfer(start: try c.decode(Vector2.self, forKey: .start), end: try c.decode(Vector2.self, forKey: .end))
        case "hole":
            self = .hole(center: try c.decode(Vector2.self, forKey: .center), radius: try c.decode(Double.self, forKey: .radius))
        case "centreMark":
            self = .centreMark(center: try c.decode(Vector2.self, forKey: .center), radius: try c.decode(Double.self, forKey: .radius))
        case "centreLine":
            self = .centreLine(start: try c.decode(Vector2.self, forKey: .start), end: try c.decode(Vector2.self, forKey: .end))
        case "leaders": self = .leaders(try c.decode([Vector2].self, forKey: .points))
        case "attachment":
            // `ends` is optional on disk (a file written before it existed has none).
            self = .attachment(
                foot: try c.decode(Vector2.self, forKey: .foot), along: try c.decode(Vector2.self, forKey: .along),
                ends: try c.decodeIfPresent([Vector2].self, forKey: .ends) ?? [])
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown figure type.")
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .linear(let points, let direction):
            try c.encode("linear", forKey: .type)
            try c.encode(points, forKey: .points)
            try c.encode(direction, forKey: .direction)
        case .ordinate(let origin, let points, let direction):
            try c.encode("ordinate", forKey: .type)
            try c.encode(origin, forKey: .origin)
            try c.encode(points, forKey: .points)
            try c.encode(direction, forKey: .direction)
        case .radial(let center, let radius, let isDiameter):
            try c.encode("radial", forKey: .type)
            try c.encode(center, forKey: .center)
            try c.encode(radius, forKey: .radius)
            try c.encode(isDiameter, forKey: .isDiameter)
        case .angle(let vertex, let first, let second):
            try c.encode("angle", forKey: .type)
            try c.encode(vertex, forKey: .vertex)
            try c.encode(first, forKey: .first)
            try c.encode(second, forKey: .second)
        case .chamfer(let start, let end):
            try c.encode("chamfer", forKey: .type)
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
        case .hole(let center, let radius):
            try c.encode("hole", forKey: .type)
            try c.encode(center, forKey: .center)
            try c.encode(radius, forKey: .radius)
        case .centreMark(let center, let radius):
            try c.encode("centreMark", forKey: .type)
            try c.encode(center, forKey: .center)
            try c.encode(radius, forKey: .radius)
        case .centreLine(let start, let end):
            try c.encode("centreLine", forKey: .type)
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
        case .leaders(let points):
            try c.encode("leaders", forKey: .type)
            try c.encode(points, forKey: .points)
        case .attachment(let foot, let along, let ends):
            try c.encode("attachment", forKey: .type)
            try c.encode(foot, forKey: .foot)
            try c.encode(along, forKey: .along)
            if !ends.isEmpty { try c.encode(ends, forKey: .ends) }
        }
    }
}

/// The newest values an annotation held: its numbers, its label lines and its figure (plan R15).
public struct LastGood: Hashable, Codable, Sendable {
    public var values: [Double]
    public var lines: [String]
    public var figure: AnnotationFigure

    public init(values: [Double], lines: [String], figure: AnnotationFigure) {
        self.values = values
        self.lines = lines
        self.figure = figure
    }
}

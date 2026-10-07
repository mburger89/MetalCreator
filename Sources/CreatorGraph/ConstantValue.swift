import CreatorGeometry

/// A value typed into an unwired input or stored as a node setting, saved in the file.
public enum ConstantValue: Hashable, Sendable {
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case vector(Vector3)
    case plane(Plane)
    /// A non-socket setting, such as the parameter a Graph Parameter node reads.
    case text(String)

    /// False for NaN or ±∞ anywhere. JSON can't store those, so commands reject them.
    public var isFinite: Bool {
        switch self {
        case .number(let value): value.isFinite
        case .vector(let vector): vector.isFinite
        case .plane(let plane): plane.origin.isFinite && plane.normal.isFinite && plane.xAxis.isFinite
        case .integer, .bool, .text: true
        }
    }
}

extension ConstantValue: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case number, integer, bool, vector, plane, text }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .number: self = .number(try container.decode(Double.self, forKey: .value))
        case .integer: self = .integer(try container.decode(Int.self, forKey: .value))
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .value))
        case .vector: self = .vector(try container.decode(Vector3.self, forKey: .value))
        case .plane: self = .plane(try container.decode(Plane.self, forKey: .value))
        case .text: self = .text(try container.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .number(let value): try container.encode(Kind.number, forKey: .type); try container.encode(value, forKey: .value)
        case .integer(let value): try container.encode(Kind.integer, forKey: .type); try container.encode(value, forKey: .value)
        case .bool(let value): try container.encode(Kind.bool, forKey: .type); try container.encode(value, forKey: .value)
        case .vector(let value): try container.encode(Kind.vector, forKey: .type); try container.encode(value, forKey: .value)
        case .plane(let value): try container.encode(Kind.plane, forKey: .type); try container.encode(value, forKey: .value)
        case .text(let value): try container.encode(Kind.text, forKey: .type); try container.encode(value, forKey: .value)
        }
    }
}

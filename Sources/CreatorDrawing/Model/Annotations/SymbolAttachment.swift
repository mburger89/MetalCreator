import Foundation

/// The three symbol kinds, for `SymbolAttachment.accepts`.
public enum SymbolKind: Hashable, Sendable {
    case datum, frame, surface
}

/// What a datum or frame stands on (plan R1, R2): a line of its view, or a dimension of the same view.
public enum SymbolAttachment: Hashable, Sendable {
    case feature(LeaderEnd)
    case dimension(AnnotationID)

    /// R2's kind rules, the one place they are written: which dimensions take which symbol.
    public static func accepts(_ symbol: SymbolKind, on dimension: DrawingAnnotation) -> Bool {
        switch dimension.kind {
        case .holeCallout: symbol != .surface
        case .dimension(let value):
            switch (symbol, value.kind) {
            case (.datum, .linear), (.datum, .diameter): true
            case (.frame, .linear), (.frame, .radius), (.frame, .diameter): true
            default: false
            }
        default: false
        }
    }
}

extension SymbolAttachment: Codable {
    private enum CodingKeys: String, CodingKey { case type, feature, dimension }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "feature": self = .feature(try c.decode(LeaderEnd.self, forKey: .feature))
        case "dimension": self = .dimension(try c.decode(AnnotationID.self, forKey: .dimension))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown attachment type.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .feature(let end):
            try c.encode("feature", forKey: .type)
            try c.encode(end, forKey: .feature)
        case .dimension(let id):
            try c.encode("dimension", forKey: .type)
            try c.encode(id, forKey: .dimension)
        }
    }
}

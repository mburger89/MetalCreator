extension AnnotationKind: Codable {
    private enum CodingKeys: String, CodingKey { case type, dimension, holeCallout, centreMark, centreLine, note }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "dimension": self = .dimension(try c.decode(DrawingDimension.self, forKey: .dimension))
        case "holeCallout": self = .holeCallout(try c.decode(HoleCallout.self, forKey: .holeCallout))
        case "centreMark": self = .centreMark(try c.decode(CentreMark.self, forKey: .centreMark))
        case "centreLine": self = .centreLine(try c.decode(CentreLine.self, forKey: .centreLine))
        case "note": self = .note(try c.decode(DrawingNote.self, forKey: .note))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown annotation kind.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dimension(let value):
            try c.encode("dimension", forKey: .type)
            try c.encode(value, forKey: .dimension)
        case .holeCallout(let value):
            try c.encode("holeCallout", forKey: .type)
            try c.encode(value, forKey: .holeCallout)
        case .centreMark(let value):
            try c.encode("centreMark", forKey: .type)
            try c.encode(value, forKey: .centreMark)
        case .centreLine(let value):
            try c.encode("centreLine", forKey: .type)
            try c.encode(value, forKey: .centreLine)
        case .note(let value):
            try c.encode("note", forKey: .type)
            try c.encode(value, forKey: .note)
        }
    }
}

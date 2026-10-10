/// `{"role": "side", "segment": k}` is an outer wall; a hole wall adds `"loop": n`. The loop is
/// written only when it isn't 0, so outer-wall tags encode exactly as they did before holes, and a
/// missing loop decodes as 0 (format version 2 files).
extension TopoRole: Codable {
    private enum CodingKeys: String, CodingKey { case role, loop, segment, edge, face }
    private enum Kind: String, Codable { case startCap, endCap, side, blend, unnamed }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .role) {
        case .startCap: self = .startCap
        case .endCap: self = .endCap
        case .side:
            let loop = try container.decodeIfPresent(Int.self, forKey: .loop) ?? 0
            guard loop >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .loop, in: container, debugDescription: "A side face's loop can't be negative.")
            }
            self = .side(loop: loop, segment: try container.decode(Int.self, forKey: .segment))
        case .blend: self = .blend(sourceEdge: try container.decode(EdgeKey.self, forKey: .edge))
        case .unnamed: self = .unnamed(face: try container.decode(Int.self, forKey: .face))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .startCap:
            try container.encode(Kind.startCap, forKey: .role)
        case .endCap:
            try container.encode(Kind.endCap, forKey: .role)
        case .side(let loop, let segment):
            guard loop >= 0 else {
                throw EncodingError.invalidValue(loop, EncodingError.Context(
                    codingPath: encoder.codingPath, debugDescription: "A side face's loop can't be negative."))
            }
            try container.encode(Kind.side, forKey: .role)
            if loop != 0 {
                try container.encode(loop, forKey: .loop)
            }
            try container.encode(segment, forKey: .segment)
        case .blend(let edge):
            try container.encode(Kind.blend, forKey: .role)
            try container.encode(edge, forKey: .edge)
        case .unnamed(let face):
            try container.encode(Kind.unnamed, forKey: .role)
            try container.encode(face, forKey: .face)
        }
    }
}

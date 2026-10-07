extension TopoRole: Codable {
    private enum CodingKeys: String, CodingKey { case role, segment, edge, face }
    private enum Kind: String, Codable { case startCap, endCap, side, blend, unnamed }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .role) {
        case .startCap: self = .startCap
        case .endCap: self = .endCap
        case .side: self = .side(segment: try container.decode(Int.self, forKey: .segment))
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
        case .side(let segment):
            try container.encode(Kind.side, forKey: .role)
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

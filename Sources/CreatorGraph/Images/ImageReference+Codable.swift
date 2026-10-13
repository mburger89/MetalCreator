extension ImageReference: Codable {
    private enum CodingKeys: String, CodingKey { case kind, hash, relativePath, absolutePath }
    private enum Kind: String, Codable { case embedded, linked }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .embedded:
            self = .embedded(try container.decode(ImageHash.self, forKey: .hash))
        case .linked:
            self = .linked(relativePath: try container.decodeIfPresent(String.self, forKey: .relativePath),
                           absolutePath: try container.decode(String.self, forKey: .absolutePath))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .embedded(let hash):
            try container.encode(Kind.embedded, forKey: .kind)
            try container.encode(hash, forKey: .hash)
        case .linked(let relativePath, let absolutePath):
            try container.encode(Kind.linked, forKey: .kind)
            try container.encodeIfPresent(relativePath, forKey: .relativePath)
            try container.encode(absolutePath, forKey: .absolutePath)
        }
    }
}

/// An element of a cutter that splits a sheet (NS-4, R2): piece `piece` of curve `index` in the cutter list as the node flattens
/// it, or a face of a cutting body by its tags. Pieces and cut edges are named by it, so a pick survives the cutter changing size.
public enum CutterName: Hashable, Sendable, Codable {
    case curve(index: Int, piece: Int)
    case face(Set<TopoTag>)

    /// A deterministic text form: `curve(i:k)`, or `face(` the tags' sort keys, sorted and joined by `+`, `)`.
    public var sortKey: String {
        switch self {
        case .curve(let index, let piece): "curve(\(index):\(piece))"
        case .face(let tags): "face(\(tags.map(\.sortKey).sorted().joined(separator: "+")))"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, index, piece, tags }
    private enum Kind: String, Codable { case curve, face }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .curve:
            self = .curve(index: try container.decode(Int.self, forKey: .index), piece: try container.decode(Int.self, forKey: .piece))
        case .face:
            self = .face(Set(try container.decode([TopoTag].self, forKey: .tags)))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .curve(let index, let piece):
            try container.encode(Kind.curve, forKey: .kind)
            try container.encode(index, forKey: .index)
            try container.encode(piece, forKey: .piece)
        case .face(let tags):
            try container.encode(Kind.face, forKey: .kind)
            try container.encode(tags.sorted { $0.sortKey < $1.sortKey }, forKey: .tags)
        }
    }

    /// The tags a `face` element names, else none.
    var nestedTags: Set<TopoTag> {
        if case .face(let tags) = self { tags } else { [] }
    }

    func mappingTags(_ transform: (TopoTag) -> TopoTag) -> CutterName {
        if case .face(let tags) = self { .face(Set(tags.map(transform))) } else { self }
    }
}

/// Which side of a cutter element a piece lies on (R2): `inside` / `outside` for an element of a closed flat curve or solid, else
/// `front` (the side the cutting surface's normal points to) / `back`.
public enum CutSide: String, Hashable, Sendable, Codable {
    case front, back, inside, outside
}

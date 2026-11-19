/// The stable role a sheet's boundary edge plays in the operation that made it (NURBS spec). An edge of a solid has two
/// faces and is named by them; a boundary edge has one, so it carries tags of its own.
public enum BoundaryRole: Hashable, Sendable, Codable {
    /// The first and last position of a sweep, extrusion, revolution or loft.
    case start, end
    /// Traced by an open curve's start (0) or end (1).
    case rail(Int)
    /// A planar surface's edge from piece `segment` of loop `loop` (0 is the outer loop, n is hole n).
    case piece(loop: Int, segment: Int)
    /// An imported sheet's boundary edge, by its index in the file's edge map.
    case imported(edge: Int)
    /// An edge a cutter made on a sheet (NS-4, R2): the element of the cutter that traced it.
    case cut(CutterName)

    private enum CodingKeys: String, CodingKey { case kind, index, loop, segment, edge, cutter }
    private enum Kind: String, Codable { case start, end, rail, piece, imported, cut }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .start: self = .start
        case .end: self = .end
        case .rail: self = .rail(try container.decode(Int.self, forKey: .index))
        case .piece:
            self = .piece(loop: try container.decode(Int.self, forKey: .loop),
                          segment: try container.decode(Int.self, forKey: .segment))
        case .imported: self = .imported(edge: try container.decode(Int.self, forKey: .edge))
        case .cut: self = .cut(try container.decode(CutterName.self, forKey: .cutter))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start: try container.encode(Kind.start, forKey: .kind)
        case .end: try container.encode(Kind.end, forKey: .kind)
        case .rail(let index):
            try container.encode(Kind.rail, forKey: .kind)
            try container.encode(index, forKey: .index)
        case .piece(let loop, let segment):
            try container.encode(Kind.piece, forKey: .kind)
            try container.encode(loop, forKey: .loop)
            try container.encode(segment, forKey: .segment)
        case .imported(let edge):
            try container.encode(Kind.imported, forKey: .kind)
            try container.encode(edge, forKey: .edge)
        case .cut(let name):
            try container.encode(Kind.cut, forKey: .kind)
            try container.encode(name, forKey: .cutter)
        }
    }

    /// A deterministic text form, used to order tags canonically.
    public var sortKey: String {
        switch self {
        case .start: "start"
        case .end: "end"
        case .rail(let index): "rail(\(index))"
        case .piece(let loop, let segment): "piece(\(loop):\(segment))"
        case .imported(let edge): "imported(\(edge))"
        case .cut(let name): "cut(\(name.sortKey))"
        }
    }
}

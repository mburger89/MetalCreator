import CreatorGeometry
import CreatorKernel

/// Which end of an edge a corner pick is.
public enum CornerEnd: String, Hashable, Sendable, Codable { case start, end, centre }

/// A section curve named by the face it was cut from and where it stands in that cut: the `index`th of `count`
/// curves, with `midpoint` to tell it from a neighbour when the cut changes.
public struct SectionEdgeAnchor: Hashable, Sendable, Codable {
    public var face: FacePick
    public var index: Int
    public var count: Int
    public var midpoint: Vector3

    public init(face: FacePick, index: Int, count: Int, midpoint: Vector3) {
        self.face = face
        self.index = index
        self.count = count
        self.midpoint = midpoint
    }
}

/// One thing a kept measurement stands on, stored without a scene: a face or edge by its tags, a corner of an edge,
/// a section curve, or a point of a mesh. Encoded as one key naming the case: `{"face":{…}}`,
/// `{"corner":{"edge":{…},"end":"start"}}`, `{"meshPoint":[x,y,z]}`.
public enum MeasureAnchor: Hashable, Sendable, Codable {
    case face(FacePick)
    case edge(EdgePick)
    case corner(EdgePick, CornerEnd)
    case sectionEdge(SectionEdgeAnchor)
    case meshSectionEdge(Vector3)
    case meshPoint(Vector3)

    private enum CodingKeys: String, CodingKey { case face, edge, corner, sectionEdge, meshSectionEdge, meshPoint }
    private enum CornerKeys: String, CodingKey { case edge, end }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let pick = try container.decodeIfPresent(FacePick.self, forKey: .face) {
            self = .face(pick)
        } else if let pick = try container.decodeIfPresent(EdgePick.self, forKey: .edge) {
            self = .edge(pick)
        } else if container.contains(.corner) {
            let inner = try container.nestedContainer(keyedBy: CornerKeys.self, forKey: .corner)
            self = .corner(try inner.decode(EdgePick.self, forKey: .edge), try inner.decode(CornerEnd.self, forKey: .end))
        } else if let anchor = try container.decodeIfPresent(SectionEdgeAnchor.self, forKey: .sectionEdge) {
            self = .sectionEdge(anchor)
        } else if let point = try container.decodeIfPresent(Vector3.self, forKey: .meshSectionEdge) {
            self = .meshSectionEdge(point)
        } else {
            self = .meshPoint(try container.decode(Vector3.self, forKey: .meshPoint))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .face(let pick): try container.encode(pick, forKey: .face)
        case .edge(let pick): try container.encode(pick, forKey: .edge)
        case let .corner(pick, end):
            var inner = container.nestedContainer(keyedBy: CornerKeys.self, forKey: .corner)
            try inner.encode(pick, forKey: .edge)
            try inner.encode(end, forKey: .end)
        case .sectionEdge(let anchor): try container.encode(anchor, forKey: .sectionEdge)
        case .meshSectionEdge(let point): try container.encode(point, forKey: .meshSectionEdge)
        case .meshPoint(let point): try container.encode(point, forKey: .meshPoint)
        }
    }
}

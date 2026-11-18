import CreatorGeometry

/// The place of one pole in a curve's or surface's control net: `i` along the first parameter, `j` along the second.
/// A curve's poles have `j == 0`. Ordered by `i`, then `j`.
public struct PoleIndex: Hashable, Comparable, Codable, Sendable {
    public var i: Int
    public var j: Int

    public init(i: Int, j: Int = 0) {
        self.i = i
        self.j = j
    }

    public static func < (lhs: PoleIndex, rhs: PoleIndex) -> Bool {
        (lhs.i, lhs.j) < (rhs.i, rhs.j)
    }
}

/// One control point moved by an offset, in millimetres, from where the input put it.
public struct PoleMove: Hashable, Codable, Sendable {
    public var index: PoleIndex
    public var offset: Vector3

    public init(index: PoleIndex, offset: Vector3) {
        self.index = index
        self.offset = offset
    }

    private enum CodingKeys: String, CodingKey { case i, j, offset }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = PoleIndex(
            i: try container.decode(Int.self, forKey: .i), j: try container.decodeIfPresent(Int.self, forKey: .j) ?? 0
        )
        offset = try container.decode(Vector3.self, forKey: .offset)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index.i, forKey: .i)
        try container.encode(index.j, forKey: .j)
        try container.encode(offset, forKey: .offset)
    }
}

/// What a sheet's one face was before its control net was read: a surface that is not a B-spline is converted exactly. The net is
/// the whole underlying surface, not just the part the face's trims show (the face's pcurves stay valid against it).
public struct SurfaceNet: Sendable {
    public var surface: BSplineSurface3D
    /// The unit normal at each pole's Greville point, in the same order as `surface.poles`, oriented by the face.
    public var normals: [Vector3]
    /// The kind the face's surface had before conversion; `nil` when it already was a B-spline.
    public var convertedFrom: SurfaceKind?

    public init(surface: BSplineSurface3D, normals: [Vector3], convertedFrom: SurfaceKind?) {
        self.surface = surface
        self.normals = normals
        self.convertedFrom = convertedFrom
    }
}

/// The kind of a curve's one piece before conversion to a B-spline.
public enum CurvePieceKind: String, Sendable { case line, arc, other }

/// A one-piece curve as one B-spline. The net is the piece's trimmed segment: an exact copy of the part of the edge's curve between
/// its ends (a trimmed or partial B-spline is cut to it), and a move of its poles is applied to that same copy. A periodic spline
/// keeps its unique poles and OpenCascade's periodic knots (`curve.isPeriodic`), so a pole's `PoleIndex` is the same on read and write.
public struct CurveNet: Sendable {
    public var curve: BSplineCurve3D
    public var isPeriodic: Bool
    /// What the piece was before conversion; `nil` when it already was a B-spline.
    public var convertedFrom: CurvePieceKind?

    public init(curve: BSplineCurve3D, isPeriodic: Bool, convertedFrom: CurvePieceKind?) {
        self.curve = curve
        self.isPeriodic = isPeriodic
        self.convertedFrom = convertedFrom
    }
}

/// A face's surface kind and, for a Bezier or B-spline surface, its net as it stands.
public struct SurfaceInfo: Sendable {
    public var kind: SurfaceKind
    public var net: BSplineSurface3D?

    public init(kind: SurfaceKind, net: BSplineSurface3D?) {
        self.kind = kind
        self.net = net
    }
}

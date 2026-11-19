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
    /// The one tolerance (mm) of control-net editing: poles this close count as one point, and an apex or a seam may open no more than
    /// this over what it was. The shim's `kNetCoincidence` (a test pins them together).
    public static let coincidence: Double = 1e-6

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

/// The degree and number of spans a rebuilt surface or curve gets in each direction (NS-3). A curve uses `degreeU` and `spansU`
/// alone. A clamped B-spline of degree d with s spans has d + s poles; a direction the source is periodic in is rebuilt periodic (s poles) and needs s > d.
public struct RebuildSpec: Hashable, Sendable {
    public var degreeU: Int
    public var degreeV: Int
    public var spansU: Int
    public var spansV: Int

    /// The highest degree a rebuild gives.
    public static let maximumDegree = 11
    /// The most poles a rebuilt surface or curve may have.
    public static let maximumPoles = 100_000

    public init(degreeU: Int, degreeV: Int, spansU: Int, spansV: Int) {
        self.degreeU = degreeU
        self.degreeV = degreeV
        self.spansU = spansU
        self.spansV = spansV
    }

    /// Refuses a degree outside 1 to 11 ("The degree must be from 1 to 11."), fewer than one span ("There must be at least 1 span.")
    /// and more than 100,000 poles in all. `forSurface` false looks at the first direction only (a curve).
    public func validate(forSurface: Bool) throws {
        let degrees = forSurface ? [degreeU, degreeV] : [degreeU]
        let spans = forSurface ? [spansU, spansV] : [spansU]
        guard degrees.allSatisfy({ (1...Self.maximumDegree).contains($0) }) else {
            throw KernelError.invalidInput("The degree must be from 1 to \(Self.maximumDegree).")
        }
        guard spans.allSatisfy({ $0 >= 1 }) else { throw KernelError.invalidInput("There must be at least 1 span.") }
        // Doubles, so a huge span count can't overflow the product.
        let count = forSurface ? Double(degreeU + spansU) * Double(degreeV + spansV) : Double(degreeU + spansU)
        if count > Double(Self.maximumPoles) {
            let total = Int(count).formatted(.number.locale(.messages))
            let limit = Self.maximumPoles.formatted(.number.locale(.messages))
            throw KernelError.invalidInput(
                "That would make \(total) control points; a \(forSurface ? "surface" : "curve") may have at most \(limit).")
        }
    }
}

/// A sheet rebuilt to a chosen degree and span count, and the largest distance from the source's surface to the result's.
public struct SurfaceRebuild: Sendable {
    public var sheet: Solid
    public var deviation: Double

    public init(sheet: Solid, deviation: Double) {
        self.sheet = sheet
        self.deviation = deviation
    }
}

/// A curve rebuilt as one spline piece, and the largest distance from the source curve to the result.
public struct CurveRebuild: Sendable {
    public var curve: Curve
    public var deviation: Double

    public init(curve: Curve, deviation: Double) {
        self.curve = curve
        self.deviation = deviation
    }
}

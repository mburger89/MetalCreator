/// How a face is parametrized by its surface (implicit spec §3.5, Face mapping): the facts the lattice nodes scale and wrap its
/// (u, v) by. A kernel reads them off the face; none of it is saved.
public struct FaceParametrization: Hashable, Sendable {
    public var kind: SurfaceKind
    /// The middle of the face's range of u and of v: the parameters measured from here are small, and a partial face's cut is far from it.
    public var uMid: Double
    public var vMid: Double
    /// Millimetres of surface per unit of u and of v: the mean of |∂S/∂u| and |∂S/∂v| over the face's range, so a cylinder's u (an
    /// angle) is its radius and a plane's is 1. Where the parametrization is not uniform (a sphere's, a cone's), this is the face's
    /// mean, which is the scale a person would call "arc length".
    public var uScale: Double
    public var vScale: Double
    /// The period of u or v when the face closes on itself in that direction (a whole cylinder, sphere or torus side), else `nil`.
    public var uPeriod: Double?
    public var vPeriod: Double?
    /// True when the surface has a degenerate edge, a pole or an apex, which is singular for any parametrization.
    public var hasDegenerateEdge: Bool

    public init(kind: SurfaceKind, uMid: Double, vMid: Double, uScale: Double, vScale: Double, uPeriod: Double? = nil,
                vPeriod: Double? = nil, hasDegenerateEdge: Bool = false) {
        self.kind = kind
        self.uMid = uMid
        self.vMid = vMid
        self.uScale = uScale
        self.vScale = vScale
        self.uPeriod = uPeriod
        self.vPeriod = vPeriod
        self.hasDegenerateEdge = hasDegenerateEdge
    }
}

/// Where a point stands against a face: the (u, v) of the nearest point of the face, and how far the point is from the surface there
/// along the face's outward normal (negative on the solid's side).
public struct FaceSample: Hashable, Sendable {
    public var u: Double
    public var v: Double
    public var depth: Double

    public init(u: Double, v: Double, depth: Double) {
        self.u = u
        self.v = v
        self.depth = depth
    }
}

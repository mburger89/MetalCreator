import CreatorGeometry

/// How a lattice's cells are laid on its region (implicit spec §3.5). The lattice is evaluated at the mapped coordinates of a point
/// instead of at the point, so a mapping is a function from space to lattice coordinates in millimetres. Straight is the identity.
///
/// Every mapping has a singular set (the axis, the polar axis) near which its stretch is unbounded. Within `exclusion` of it the
/// lattice is left solid, and between `exclusion` and `exclusion + fadeWidth` the lattice fades into the solid (`join`), which is what
/// keeps the value Lipschitz: the lattice is only ever read where the stretch is bounded.
///
/// Adding a case means adding it to every `switch` here and in the CPU evaluator and the compiler, none of which has a `default`.
public enum LatticeMapping: Hashable, Sendable {
    case straight
    case cylindrical(CylindricalMap)
    case spherical(SphericalMap)
    case face(FaceMap)

    /// How near the singular set the lattice is left solid, in millimetres (spec §3.5).
    public static let exclusion = 1.0
    /// How far beyond the exclusion the lattice fades in, in millimetres.
    public static let fadeWidth = 0.5
    /// How far past the region's box the stretch is bounded: the evaluator's octree pads the box by a voxel, and the coarsest preview
    /// voxel of a part up to 500 mm is under 4 mm.
    public static let margin = 4.0

    /// The lattice coordinates of `p`, in millimetres.
    public func coordinates(at p: Vector3) -> Vector3 {
        switch self {
        case .straight: p
        case .cylindrical(let map): map.coordinates(at: p)
        case .spherical(let map): map.coordinates(at: p)
        case .face(let map): map.coordinates(at: p)
        }
    }

    /// The distance from `p` to the mapping's singular set; infinite for Straight.
    public func singularDistance(at p: Vector3) -> Double {
        switch self {
        case .straight: .infinity
        case .cylindrical(let map): map.singularDistance(at: p)
        case .spherical(let map): map.singularDistance(at: p)
        case .face(let map): map.singularDistance(at: p)
        }
    }

    /// The largest stretch of the mapping (the largest singular value of its Jacobian) over the region and its margin, outside the
    /// exclusion: a constant S ≥ 1 bounding that largest singular value. It gives |M(a) − M(b)| ≤ S · |a − b| only where the segment
    /// from a to b stays outside the exclusion, not globally. Computed when the mapping is built; 1 for Straight.
    public var stretch: Double {
        switch self {
        case .straight: 1
        case .cylindrical(let map): map.stretch
        case .spherical(let map): map.stretch
        case .face(let map): map.stretch
        }
    }

    /// An upper bound of |M(p)| over the region and its margin, for a graded cell size's warp; `straight` for Straight (the caller's
    /// own bound of |p|).
    public func reach(straight: Double) -> Double {
        switch self {
        case .straight: straight
        case .cylindrical(let map): map.reach
        case .spherical(let map): map.reach
        case .face(let map): map.reach
        }
    }

    /// True when the region comes close enough to the singular set for the clipping to matter.
    public var reachesSingularity: Bool {
        switch self {
        case .straight: false
        case .cylindrical(let map): map.reachesSingularity
        case .spherical(let map): map.reachesSingularity
        case .face(let map): map.chart.hasSingular
        }
    }

    /// What the warning calls the singular set: "The mapping is singular near …; cells there are left solid." `nil` for Straight.
    public var singularNoun: String? {
        switch self {
        case .straight: nil
        case .cylindrical: "the axis"
        case .spherical: "the polar axis"
        case .face(let map): map.chart.hasSingular ? map.chart.singularNoun : nil
        }
    }

    /// The length of one turn of the first and the second lattice coordinate where it closes on itself (the pattern must repeat
    /// there for the cells to meet), else `nil`. Voronoi seeds are copied across the cut by it.
    public var periods: (first: Double?, second: Double?) {
        switch self {
        case .straight: (nil, nil)
        case .cylindrical(let map): (map.turn, nil)
        case .spherical(let map): (map.turn, nil)
        case .face(let map): map.turns
        }
    }

    /// The lattice's `body` at `p` with the singular set left solid: the body where the point is more than `exclusion + fadeWidth`
    /// from it, solid (`distance − exclusion`, which is 0 or less) within `exclusion`, and a blend in between. The body is never read
    /// within `exclusion`, so its unbounded stretch there cannot reach the result.
    public func join(_ body: Double, at p: Vector3) -> Double {
        guard case .straight = self else {
            let distance = singularDistance(at: p)
            let weight = min(max((distance - Self.exclusion) / Self.fadeWidth, 0), 1)
            if weight >= 1 { return body }
            let solid = distance - Self.exclusion
            return weight <= 0 ? solid : weight * body + (1 - weight) * solid
        }
        return body
    }

    /// The lipschitz constant of a lattice whose own constant is `base` (already multiplied by `stretch`) after `join`: the blend adds
    /// the solid's slope and the change of the weight times the largest gap between the body and the solid.
    /// - Parameter valueBound: a bound of |body| on the lattice.
    public func lipschitz(base: Double, valueBound: Double) -> Double {
        guard reachesSingularity else { return base }
        return base + singularSlope + (valueBound + Self.fadeWidth) * singularSlope / Self.fadeWidth
    }

    /// How fast the distance to the singular set can change per millimetre: 1 for a distance to a line, a little more for a chart's.
    var singularSlope: Double {
        if case .face(let map) = self { map.singularSlope } else { 1 }
    }
}

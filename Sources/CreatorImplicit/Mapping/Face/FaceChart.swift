import CreatorGeometry
import CreatorKernel

/// A face measured on a grid (implicit spec §3.5, Face mapping; §4.4: projections are baked into `DistanceBlocks`): at every sample,
/// where the nearest point of the face is in (u, v), and how far the sample is from the surface along the face's normal. Evaluation
/// is then a lookup, however curved the face.
///
/// A coordinate in which the face closes on itself (a whole cylinder's angle) is stored as the cosine and sine of its angle, which
/// interpolate across the seam where the angle itself would jump; the others are stored in millimetres from the face's middle.
/// Made once per face and tolerance (`FaceChartCache`) and equal by identity.
public final class FaceChart: Hashable, Sendable {
    /// A cell is singular, and the lattice is left solid there, when the map stretches by more than this: it is where the face's centre
    /// of curvature, a pole or an apex is (spec §3.5), measured instead of derived for every kind of surface.
    public static let stretchLimit = 25.0
    /// The singular distance is held to this: farther than the exclusion and its fade, it does not matter.
    public static let singularCap = 4.0

    public let bounds: BoundingBox
    public let spacing: Double
    public let kind: SurfaceKind
    public let hasDegenerateEdge: Bool
    /// The first coordinate: millimetres from the face's middle along u, or (periodic) the cosine of its angle, with `firstSine`.
    public let first: DistanceBlocks
    public let firstSine: DistanceBlocks?
    public let second: DistanceBlocks
    public let secondSine: DistanceBlocks?
    /// The signed distance along the face's outward normal.
    public let depth: DistanceBlocks
    /// The distance to the nearest singular cell, held to `singularCap`; `nil` when there is none.
    public let singular: DistanceBlocks?
    /// The length in millimetres of one turn of a periodic coordinate, as the face has it (the period times the mean scale).
    public let firstTurn: Double?
    public let secondTurn: Double?
    /// The largest change per millimetre of each coordinate over the cells that are not singular: millimetres per millimetre, or radians
    /// per millimetre for a periodic one.
    public let firstSlope: Double
    public let secondSlope: Double
    public let depthSlope: Double
    /// The largest absolute value of each (millimetres; a periodic coordinate's is its turn over 2).
    public let firstExtent: Double
    public let secondExtent: Double
    public let depthExtent: Double
    /// A coarse set of positions on the singular cells (every one, thinned past 4096), for asking a region box whether it holds any.
    public let singularPoints: [Vector3]

    public init(bounds: BoundingBox, spacing: Double, kind: SurfaceKind, hasDegenerateEdge: Bool, first: DistanceBlocks,
                firstSine: DistanceBlocks?, second: DistanceBlocks, secondSine: DistanceBlocks?, depth: DistanceBlocks,
                singular: DistanceBlocks?, firstTurn: Double?, secondTurn: Double?, slopes: (first: Double, second: Double, depth: Double),
                extents: (first: Double, second: Double, depth: Double), singularPoints: [Vector3]) {
        self.bounds = bounds
        self.spacing = spacing
        self.kind = kind
        self.hasDegenerateEdge = hasDegenerateEdge
        self.first = first
        self.firstSine = firstSine
        self.second = second
        self.secondSine = secondSine
        self.depth = depth
        self.singular = singular
        self.firstTurn = firstTurn
        self.secondTurn = secondTurn
        firstSlope = slopes.first
        secondSlope = slopes.second
        depthSlope = slopes.depth
        firstExtent = extents.first
        secondExtent = extents.second
        depthExtent = extents.depth
        self.singularPoints = singularPoints
    }

    /// True when some cell is singular.
    public var hasSingular: Bool { singular != nil }

    /// What the warning calls the singular set: "The mapping is singular near …; cells there are left solid."
    public var singularNoun: String {
        if hasDegenerateEdge { return "the face's singular edge" }
        return switch kind {
        case .cylinder: "the cylinder's axis"
        case .cone: "the cone's axis"
        case .sphere: "the sphere's centre"
        case .torus: "the torus's core circle"
        case .plane, .bspline, .other: "the face's centre of curvature"
        }
    }

    /// The blocks, for the memory count and the GPU.
    public var allBlocks: [DistanceBlocks] {
        [first, firstSine, second, secondSine, depth, singular].compactMap { $0 }
    }

    public var estimatedBytes: Int { allBlocks.reduce(0) { $0 + $1.estimatedBytes } + 256 }

    public static func == (lhs: FaceChart, rhs: FaceChart) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

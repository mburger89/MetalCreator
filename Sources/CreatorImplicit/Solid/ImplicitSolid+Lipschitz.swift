extension ImplicitSolid {
    /// A constant L ≥ 1 with |f(a) − f(b)| ≤ L · |a − b| (implicit spec §2.1, §3.3). Primitives and moves are exact; a baked
    /// distance has the slope bound of its interpolation (`DistanceBlocks.lipschitz`). A smooth blend takes the largest of its children's plus a quarter of the blend radius's slope (the blend term
    /// k·h²/4 changes by at most a quarter per unit of k). An offset or a shell takes its child's times one plus the slope of its
    /// distance. An isosurface divides the field's slope by `maxSlope`.
    public var lipschitz: Double {
        switch self {
        case .sphere, .box, .cylinder:
            return 1
        case .baked(let blocks, _):
            return blocks.lipschitz
        case .moved(let child, _):
            return child.lipschitz
        case .union(let children, let blend), .intersect(let children, let blend), .subtract(let children, let blend):
            return max(1, children.map(\.lipschitz).max() ?? 1) + blend.slope / 4
        case .offset(let child, let distance):
            return child.lipschitz * (1 + distance.slope)
        case .shell(let child, let thickness, _):
            return child.lipschitz * (1 + thickness.slope)
        case .isosurface(let grading, _, let maxSlope, _):
            return max(1, grading.slope / maxSlope)
        case .tpms(let lattice):
            return lattice.lipschitz
        case .struts(let lattice):
            return lattice.lipschitz
        case .voronoi(let lattice):
            return lattice.lipschitz
        }
    }

    /// How far from the surface the value is the true distance (infinite for an analytic solid). A baked distance is exact within
    /// its band, and an offset or a shell reads the child that far plus its own distance, so they shorten it. Shell and Offset warn
    /// when their distance reaches past it.
    public var exactReach: Double {
        switch self {
        case .sphere, .box, .cylinder, .isosurface, .tpms, .struts, .voronoi:
            return .infinity
        case .moved(let child, _):
            return child.exactReach
        case .union(let children, _), .intersect(let children, _), .subtract(let children, _):
            return children.map(\.exactReach).min() ?? .infinity
        case .offset(let child, let distance):
            return max(0, child.exactReach - distance.magnitude)
        case .shell(let child, let thickness, _):
            return max(0, child.exactReach - thickness.magnitude)
        case .baked(let blocks, _):
            return blocks.band
        }
    }
}

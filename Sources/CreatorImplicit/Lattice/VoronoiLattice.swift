import CreatorGeometry

/// A Voronoi lattice of `seeds` filling `region`'s box (implicit spec §3.4). With R the search radius and d₁ ≤ d₂ ≤ d₃ the distances
/// to the three nearest seeds, all of them capped at R:
/// - **Struts**: (d₃ − d₁) ÷ `strutScale` − thickness ÷ 2. d₃ − d₁ is 0 exactly where three cells meet (the cell edges), and grows
///   1.5 per millimetre away from an edge where three equal cells meet at 120°, which is `strutScale`.
/// - **Foam**: the distance to the nearest cell wall, the smallest over the other seeds of the distance to the plane half way to
///   them, capped at (R − d₁) ÷ 2 (a wall farther away than that may belong to a seed beyond the search), minus thickness ÷ 2.
/// Both are window-independent: a point with no seed within R reads as on a wall (solid), and the node warns about such gaps.
public struct VoronoiLattice: Hashable, Sendable {
    /// d₃ − d₁ grows by 1.5 per millimetre from an edge of three equal cells: the divisor that turns it into millimetres.
    public static let strutScale = 1.5

    public var seeds: VoronoiSeeds
    public var form: VoronoiForm
    /// The strut diameter or the wall thickness, in millimetres; a negative value counts as 0.
    public var thickness: Grading
    public var region: BoundingBox

    public init(seeds: VoronoiSeeds, form: VoronoiForm, thickness: Grading, region: BoundingBox) {
        self.seeds = seeds
        self.form = form
        self.thickness = thickness
        self.region = region
    }

    /// The distance to a wall is 1-Lipschitz (a minimum of distances to planes, capped by a half-slope term); d₃ − d₁ is 2-Lipschitz;
    /// the thickness field adds half its slope.
    public var lipschitz: Double {
        let base = switch form {
        case .struts: 2 / Self.strutScale
        case .foam: 1.0
        }
        return max(1, base + thickness.slope / 2)
    }
}

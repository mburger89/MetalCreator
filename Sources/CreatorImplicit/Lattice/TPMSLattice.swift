import CreatorGeometry

/// A triply periodic minimal surface lattice filling `region`'s box (implicit spec §3.4). Its value is
/// `max(wall, distance to the region box)`, where the wall is `|core| − thickness / 2` for a sheet and `core − thickness / 2` for a
/// network, and `core = g(2π p / (size × stretch)) × size / (2π × wallScale)` is g scaled to millimetres. The TPMS node intersects it
/// with the real region and adds the skin; this is only the lattice, cut off at the region's box so that its bounds are finite.
public struct TPMSLattice: Hashable, Sendable {
    public var type: TPMSType
    public var form: TPMSForm
    public var cells: LatticeCells
    /// The wall thickness (sheet) or the offset of the level (network), in millimetres; a negative value counts as 0.
    public var thickness: Grading
    /// The box the lattice is cut to.
    public var region: BoundingBox
    /// How the cells are laid on the region (implicit spec §3.5); Straight evaluates the pattern at the point itself.
    public var mapping: LatticeMapping

    public init(type: TPMSType, form: TPMSForm, cells: LatticeCells, thickness: Grading, region: BoundingBox,
                mapping: LatticeMapping = .straight) {
        self.type = type
        self.form = form
        self.cells = cells
        self.thickness = thickness
        self.region = region
        self.mapping = mapping
    }

    /// A constant L ≥ 1 with |f(a) − f(b)| ≤ L · |a − b|. Differentiating `core` gives (|∇g| ÷ wallScale) ÷ the smallest stretch
    /// times `cells.warp` for the moving lattice coordinates (a mapping multiplies the point's own motion by its stretch, and its
    /// coordinates reach farther than the point does), plus |g| × the size field's slope ÷ (2π × wallScale) for the changing scale, plus
    /// half the thickness field's slope; a mapping that can reach its singular set adds what `LatticeMapping.lipschitz` says.
    public var lipschitz: Double {
        let warp = cells.warp(reach: mapping.reach(straight: LatticeCells.reach(of: region)), stretch: mapping.stretch)
        let moving = type.gradientBound / (type.wallScale * cells.smallestStretch) * warp
        let scaling = type.valueBound * cells.size.slope / (2 * Double.pi * type.wallScale)
        return mapping.lipschitz(base: max(1, moving + scaling + thickness.slope / 2), valueBound: valueBound)
    }

    /// A bound on |wall| before the region cut: |g| scaled to millimetres, plus half the thickness.
    public var valueBound: Double {
        type.valueBound * cells.size.range.upperBound / (2 * Double.pi * type.wallScale) + thickness.magnitude / 2
    }
}

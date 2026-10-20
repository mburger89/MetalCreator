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

    public init(type: TPMSType, form: TPMSForm, cells: LatticeCells, thickness: Grading, region: BoundingBox) {
        self.type = type
        self.form = form
        self.cells = cells
        self.thickness = thickness
        self.region = region
    }

    /// A constant L ≥ 1 with |f(a) − f(b)| ≤ L · |a − b|. Differentiating `core` gives (|∇g| ÷ wallScale) ÷ the smallest stretch
    /// times `cells.warp` for the moving lattice coordinates, plus |g| × the size field's slope ÷ (2π × wallScale) for the changing
    /// scale, plus half the thickness field's slope.
    public var lipschitz: Double {
        let warp = cells.warp(reach: LatticeCells.reach(of: region))
        let moving = type.gradientBound / (type.wallScale * cells.smallestStretch) * warp
        let scaling = type.valueBound * cells.size.slope / (2 * Double.pi * type.wallScale)
        return max(1, moving + scaling + thickness.slope / 2)
    }
}

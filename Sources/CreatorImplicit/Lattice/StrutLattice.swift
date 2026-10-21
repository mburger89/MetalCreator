import CreatorGeometry

/// A lattice of straight struts of radius `radius` filling `region`'s box (implicit spec §3.4). Its value is the distance to the
/// nearest strut less the radius, where the struts are those of the current cell and its 26 neighbours (a strut crosses cell faces),
/// capped at 0.85 of the smallest cell edge, which is as far as that window sees. `blend` rounds the joints with the polynomial smooth
/// minimum. Cut to the region's box.
public struct StrutLattice: Hashable, Sendable {
    public var cell: StrutCell
    public var cells: LatticeCells
    /// The strut radius in millimetres; a negative value counts as 0.
    public var radius: Grading
    /// The width of the smooth minimum over the struts, 0 for sharp joints.
    public var blend: Double
    public var region: BoundingBox
    /// How the cells are laid on the region (implicit spec §3.5); Straight evaluates the struts at the point itself.
    public var mapping: LatticeMapping

    /// How far, in cells, the window of 27 cells sees from any point: every strut outside it is at least `1 - StrutCell.spill`
    /// cells away, and the value is capped a little short of that.
    public static let reachInCells = 0.85

    public init(cell: StrutCell, cells: LatticeCells, radius: Grading, blend: Double, region: BoundingBox,
                mapping: LatticeMapping = .straight) {
        self.cell = cell
        self.cells = cells
        self.radius = radius
        self.blend = blend
        self.region = region
        self.mapping = mapping
    }

    /// The distance to the lattice is 1-Lipschitz for a fixed cell size; a graded size moves the struts by their coordinates times the
    /// size field's slope over the size (`LatticeCells.warp`, with the window's reach added to the region's), and the radius field's
    /// slope is added. A mapping multiplies the distance by its stretch (the struts sit in lattice coordinates) and a mapping that can
    /// reach its singular set adds what `LatticeMapping.lipschitz` says.
    public var lipschitz: Double {
        let largest = max(cells.size.range.upperBound, cells.smallest) * max(cells.stretch.x, cells.stretch.y, cells.stretch.z)
        let warp = cells.warp(reach: mapping.reach(straight: LatticeCells.reach(of: region)) + 2 * largest, stretch: mapping.stretch)
        return mapping.lipschitz(base: max(1, warp + radius.slope), valueBound: valueBound)
    }

    /// A bound on |value| before the region cut: the cap of the window's reach, or the radius if that is more.
    public var valueBound: Double {
        let largest = max(cells.size.range.upperBound, cells.smallest) * max(cells.stretch.x, cells.stretch.y, cells.stretch.z)
        return max(Self.reachInCells * largest, radius.magnitude)
    }
}

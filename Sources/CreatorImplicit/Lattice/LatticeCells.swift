import CreatorGeometry
import Foundation

/// How big a lattice's cells are (implicit spec §3.4): a cell size in millimetres that a field may grade, and a stretch that makes the
/// cells longer or shorter along an axis. The cell size is the geometric mean of the three cell edges and the stretch has geometric
/// mean 1, so a stretch changes a cell's shape and not its volume.
///
/// The lattice coordinates of a point are `p / (size(p) × stretch)`, so where the field changes fast the pattern stretches with it
/// (implicit spec §3.4). The pattern is anchored at the world origin, which keeps it still when the region is edited.
public struct LatticeCells: Hashable, Sendable {
    /// The cell size at each point, in millimetres.
    public var size: Grading
    /// The factor on each axis, with geometric mean 1.
    public var stretch: Vector3

    /// - Parameter stretch: the proportions of a cell; scaled to geometric mean 1. A component that is not a positive number counts
    ///   as 1.
    public init(size: Grading, stretch: Vector3 = Vector3(1, 1, 1)) {
        self.size = size
        func positive(_ value: Double) -> Double { value.isFinite && value > 0 ? value : 1 }
        let (x, y, z) = (positive(stretch.x), positive(stretch.y), positive(stretch.z))
        let mean = cbrt(x * y * z)
        self.stretch = Vector3(x / mean, y / mean, z / mean)
    }

    /// The smallest cell size the grading takes, never below a micrometre (the evaluator guards the division with it).
    public var smallest: Double { max(size.range.lowerBound, Self.minimumSize) }

    /// The smallest stretch factor.
    public var smallestStretch: Double { min(stretch.x, stretch.y, stretch.z) }

    /// The smallest a cell size is taken to be, in millimetres.
    public static let minimumSize = 1e-6

    /// The distance from the world origin to the farthest corner of `box`: the lattice coordinates `p / size(p)` move by up to this
    /// much times the size field's slope per millimetre, which is what a graded size adds to the lipschitz constant.
    public static func reach(of box: BoundingBox) -> Double {
        let corners = [box.min, box.max]
        return corners.flatMap { a in corners.flatMap { b in corners.map { c in Vector3(a.x, b.y, c.z).length } } }.max() ?? 0
    }

    /// 1 plus how much the size field's change moves a lattice coordinate, over a region at most `reach` from the origin: the factor
    /// the distance to the pattern's surface is multiplied by (implicit spec §3.4: "the lipschitz bound grows with the field's slope").
    public func warp(reach: Double) -> Double { 1 + reach * size.slope / smallest }
}

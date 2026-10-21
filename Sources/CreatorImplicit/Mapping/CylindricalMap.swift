import CreatorGeometry
import Foundation

/// The cylindrical mapping (implicit spec §3.5): the lattice coordinates of a point are (angle × `radius`, height, distance from the
/// axis), so cells wrap around the axis. The axis is a plane's normal through its origin and the angle is measured from the plane's x
/// axis, counter-clockwise seen from the normal's tip; the angle's cut is the half-plane opposite the x axis.
///
/// `radius` is the radius the angle is multiplied by. For a lattice with a cell size it is the region's mean radius rounded so that a
/// whole number of cells goes round (`LatticeMapping.turnRadius(mean:cell:)`), which makes the pattern meet itself at the cut.
public struct CylindricalMap: Hashable, Sendable {
    /// A point of the axis.
    public let origin: Vector3
    /// The frame: `reference` is the direction the angle is measured from, `side` is 90° counter-clockwise from it, and `axis` is the
    /// unit direction of the axis.
    public let reference: Vector3
    public let side: Vector3
    public let axis: Vector3
    public let radius: Double
    /// A constant S ≥ 1 bounding the largest singular value of the Jacobian of M wherever the point is at least
    /// `LatticeMapping.exclusion` from the axis, over the region grown by `LatticeMapping.margin`. It bounds |M(a) − M(b)| ≤ S · |a − b|
    /// only for a segment that stays outside the exclusion (and clear of the longitude cut); it is not a global bound. Computed when
    /// the mapping is built.
    public let stretch: Double
    /// An upper bound of the length of the mapped coordinates over the region (for the graded cell size's warp).
    public let reach: Double
    /// True when the region comes within the exclusion and its fade of the axis, so the clipping is in play.
    public let reachesSingularity: Bool

    /// - Parameters:
    ///   - plane: its normal through its origin is the axis, its x axis the angle's start.
    ///   - radius: the angle's multiplier, more than 0.
    ///   - region: the box the lattice fills.
    /// - Returns: `nil` for a plane with no usable direction or a radius that is not a positive number.
    public init?(axis plane: Plane, radius: Double, over region: BoundingBox) {
        guard radius.isFinite, radius > 0, let frame = RigidMove(plane: plane) else { return nil }
        origin = frame.origin
        reference = frame.xAxis
        side = frame.yAxis
        axis = frame.zAxis
        self.radius = radius
        let box = ImplicitSolid.grown(region, by: LatticeMapping.margin)
        let range = BoxProjection.radialRange(of: box, origin: frame.origin, xAxis: frame.xAxis, yAxis: frame.yAxis)
        let height = BoxProjection.corners(of: box).map { abs(($0 - frame.origin).dot(frame.zAxis)) }.max() ?? 0
        reach = (Double.pi * radius * Double.pi * radius + height * height + range.farthest * range.farthest).squareRoot()
        stretch = max(1, radius / max(range.nearest, LatticeMapping.exclusion))
        reachesSingularity = range.nearest < LatticeMapping.exclusion + LatticeMapping.fadeWidth
    }

    /// (angle × radius, height, distance from the axis) of `p`. At the axis the angle is taken as 0.
    public func coordinates(at p: Vector3) -> Vector3 {
        let offset = p - origin
        let (x, y) = (offset.dot(reference), offset.dot(side))
        return Vector3(atan2(y, x) * radius, offset.dot(axis), (x * x + y * y).squareRoot())
    }

    /// The distance from the axis.
    public func singularDistance(at p: Vector3) -> Double {
        let offset = p - origin
        let (x, y) = (offset.dot(reference), offset.dot(side))
        return (x * x + y * y).squareRoot()
    }

    /// The length of one turn of the first coordinate.
    public var turn: Double { 2 * Double.pi * radius }
}

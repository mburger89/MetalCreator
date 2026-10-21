import CreatorGeometry
import Foundation

/// The spherical mapping (implicit spec §3.5): the lattice coordinates of a point are (longitude × `radius`, latitude × `radius`,
/// distance from the centre). The polar axis is the world Z axis through the centre; longitude is measured from +X, counter-clockwise
/// seen from +Z, with its cut on the half-plane toward −X; latitude is 0 on the equator and ±90° at the poles.
public struct SphericalMap: Hashable, Sendable {
    public let centre: Vector3
    public let radius: Double
    /// See `CylindricalMap.stretch`; the singular set is the polar axis.
    public let stretch: Double
    public let reach: Double
    public let reachesSingularity: Bool

    /// - Returns: `nil` for a centre that is not finite or a radius that is not a positive number.
    public init?(centre: Vector3, radius: Double, over region: BoundingBox) {
        guard radius.isFinite, radius > 0, centre.isFinite else { return nil }
        self.centre = centre
        self.radius = radius
        let box = ImplicitSolid.grown(region, by: LatticeMapping.margin)
        let (dx, dy) = (max(box.min.x - centre.x, 0, centre.x - box.max.x), max(box.min.y - centre.y, 0, centre.y - box.max.y))
        let nearest = (dx * dx + dy * dy).squareRoot()
        let farthest = BoxProjection.corners(of: box).map { ($0 - centre).length }.max() ?? 0
        let angles = Double.pi * radius
        reach = (angles * angles + angles * angles / 4 + farthest * farthest).squareRoot()
        stretch = max(1, radius / max(nearest, LatticeMapping.exclusion))
        reachesSingularity = nearest < LatticeMapping.exclusion + LatticeMapping.fadeWidth
    }

    /// (longitude × radius, latitude × radius, distance from the centre) of `p`. On the polar axis the longitude is taken as 0.
    public func coordinates(at p: Vector3) -> Vector3 {
        let offset = p - centre
        let across = (offset.x * offset.x + offset.y * offset.y).squareRoot()
        return Vector3(atan2(offset.y, offset.x) * radius, atan2(offset.z, across) * radius, offset.length)
    }

    /// The distance from the polar axis.
    public func singularDistance(at p: Vector3) -> Double {
        let offset = p - centre
        return (offset.x * offset.x + offset.y * offset.y).squareRoot()
    }

    /// The length of one turn of the first coordinate.
    public var turn: Double { 2 * Double.pi * radius }
}

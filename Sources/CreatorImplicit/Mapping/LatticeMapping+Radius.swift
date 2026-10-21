import CreatorGeometry
import Foundation

extension LatticeMapping {
    /// Samples across each axis when the mean radius of a region is measured.
    public static let radiusSamples = 24

    /// The region's mean radius (implicit spec §3.5): the mean of `distance` (the distance from the axis or from the centre) over the
    /// points of a 24 × 24 × 24 grid through the region's box that lie inside the region. A region too thin for any grid point falls
    /// back to the distance at the box's centre. At least `exclusion`, so the result is a usable radius.
    public static func meanRadius(of region: ImplicitSolid, distance: (Vector3) -> Double) -> Double {
        let box = region.bounds
        let steps = radiusSamples
        var points: [Vector3] = []
        points.reserveCapacity(steps * steps * steps)
        for k in 0..<steps {
            for j in 0..<steps {
                for i in 0..<steps {
                    points.append(box.min + Vector3(box.size.x * (Double(i) + 0.5) / Double(steps),
                                                    box.size.y * (Double(j) + 0.5) / Double(steps),
                                                    box.size.z * (Double(k) + 0.5) / Double(steps)))
                }
            }
        }
        let values = region.signedDistances(at: points)
        var (sum, count) = (0.0, 0)
        for (point, value) in zip(points, values) where value < 0 {
            sum += distance(point)
            count += 1
        }
        let mean = count > 0 ? sum / Double(count) : distance(box.center)
        return max(mean, exclusion)
    }

    /// The radius a turn is wound on so that a whole number of cells goes round: `mean` rounded so that 2π × radius is the nearest
    /// whole multiple of `cell` (at least one). With no `cell` (a Voronoi lattice has none) it is `mean`.
    /// - Parameter cell: the nominal length of a cell along the angle, in millimetres.
    public static func turnRadius(mean: Double, cell: Double?) -> Double {
        guard let cell, cell > 0, cell.isFinite else { return mean }
        let cells = max(1, (2 * Double.pi * mean / cell).rounded())
        return cells * cell / (2 * Double.pi)
    }
}

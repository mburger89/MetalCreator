import CreatorGeometry
import Foundation

/// The Face mapping (implicit spec §3.5): the lattice coordinates of a point are the (u, v) of the nearest point of the face in
/// millimetres and the signed distance to the face along its normal, so cells follow the skin. Everything is read from a baked
/// `FaceChart`; where a coordinate closes on itself (a whole cylinder's angle) the turn is wound on a radius that makes a whole number
/// of cells go round, as the Cylindrical mapping does.
public struct FaceMap: Hashable, Sendable {
    public let chart: FaceChart
    /// Millimetres per radian of a periodic first / second coordinate after rounding the turn to whole cells; `nil` if it is not periodic.
    public let firstRadius: Double?
    public let secondRadius: Double?
    /// See `CylindricalMap.stretch`: from the chart's slopes over the cells that are not singular.
    public let stretch: Double
    public let reach: Double

    /// - Parameters:
    ///   - firstCell: the nominal length of a cell along the first coordinate, for rounding its turn; `nil` for none (Voronoi).
    ///   - secondCell: the same for the second.
    public init(chart: FaceChart, firstCell: Double?, secondCell: Double?) {
        self.chart = chart
        func radius(_ turn: Double?, _ cell: Double?) -> Double? {
            turn.map { LatticeMapping.turnRadius(mean: $0 / (2 * Double.pi), cell: cell) }
        }
        firstRadius = radius(chart.firstTurn, firstCell)
        secondRadius = radius(chart.secondTurn, secondCell)
        let slopes = (chart.firstSlope * (firstRadius ?? 1), chart.secondSlope * (secondRadius ?? 1), chart.depthSlope)
        stretch = max(1, (slopes.0 * slopes.0 + slopes.1 * slopes.1 + slopes.2 * slopes.2).squareRoot())
        let extents = (firstRadius.map { Double.pi * $0 } ?? chart.firstExtent, secondRadius.map { Double.pi * $0 } ?? chart.secondExtent,
                       chart.depthExtent)
        reach = (extents.0 * extents.0 + extents.1 * extents.1 + extents.2 * extents.2).squareRoot()
    }

    /// (u, v, depth) of `p` in millimetres: the face's coordinates at the nearest point, and the signed distance along its normal.
    public func coordinates(at p: Vector3) -> Vector3 {
        func value(_ cosine: DistanceBlocks, _ sine: DistanceBlocks?, _ radius: Double?) -> Double {
            guard let sine, let radius else { return cosine.channelValue(at: p) }
            return atan2(sine.channelValue(at: p), cosine.channelValue(at: p)) * radius
        }
        return Vector3(value(chart.first, chart.firstSine, firstRadius), value(chart.second, chart.secondSine, secondRadius),
                       chart.depth.channelValue(at: p))
    }

    /// The distance to the nearest singular cell of the chart; infinite when it has none.
    public func singularDistance(at p: Vector3) -> Double { chart.singular?.channelValue(at: p) ?? .infinity }

    /// How fast `singularDistance` can change: the chart's distance is a chamfer distance, a little over 1-Lipschitz.
    public var singularSlope: Double { chart.singular?.lipschitz ?? 1 }

    /// The length of one turn of a periodic coordinate.
    public var turns: (first: Double?, second: Double?) {
        (firstRadius.map { 2 * Double.pi * $0 }, secondRadius.map { 2 * Double.pi * $0 })
    }
}

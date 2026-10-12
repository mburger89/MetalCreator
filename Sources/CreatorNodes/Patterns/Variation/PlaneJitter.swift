import CreatorGeometry
import Foundation

/// One placement nudged at random inside its own plane and turned about its own normal (patterns spec §4).
///
/// Three draws of the item's stream make the move: draw `3p` picks the distance, `3p + 1` the direction and `3p + 2` the turn,
/// `p` being the item's index in its branch. The offset is a point in a disc of radius `distance` (the distance is the
/// square root of the first draw times the limit, so the points spread evenly over the disc rather than crowding its middle);
/// the turn is anywhere from −`turn` to `turn`. The offset goes along the plane's own axes, before the turn.
enum PlaneJitter {
    static func jittered(_ plane: Plane, random: SeededRandom, index: Int, distance: Double, turn: Double) -> Plane {
        let radius = distance * random.unit(at: 3 * index).squareRoot()
        let direction = 2 * Double.pi * random.unit(at: 3 * index + 1)
        let angle = (2 * random.unit(at: 3 * index + 2) - 1) * turn * Double.pi / 180
        let (x, y) = (plane.xAxis, plane.yAxis)
        let origin = plane.origin + x * (radius * cos(direction)) + y * (radius * sin(direction))
        return Plane(origin: origin, normal: plane.normal, xAxis: x * cos(angle) + y * sin(angle))
    }
}

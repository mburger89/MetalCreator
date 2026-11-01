import Foundation
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport

/// A full circle edge's centre, as the snap tests the pointer against it.
struct CircleCentre: Equatable {
    var solid: Int
    var edge: EdgeID
    var centre: Vector3
    var curve: EdgeCurve
}

private extension ScreenPoint {
    func distance(to other: ScreenPoint) -> Double { ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot() }
}

enum MeasureSnap {
    /// The pick under the pointer: a corner when an edge's end (or a closed circle's centre) is within `radius` points.
    static func pick(for target: PickTarget?, at point: ScreenPoint, topology: Topology?, mesh: DisplayMesh?,
                     screenPoint: (Vector3) -> ScreenPoint?, radius: Double = 10) -> MeasurePick? {
        switch target {
        case nil: return nil
        case let .face(solid, id)?: return .face(solid: solid, id)
        case let .edge(solid, id)?:
            var best: (end: CornerEnd, at: Vector3, distance: Double)?
            for candidate in ends(of: id, topology: topology, mesh: mesh) {
                guard let screen = screenPoint(candidate.at) else { continue }
                let distance = screen.distance(to: point)
                // A circle's centre is near its rim only on a small circle, which must still pick as its edge.
                var reach = radius
                if candidate.end == .centre, let circle = topology?.edge(id)?.curve,
                   let onScreen = screenRadius(of: circle, screenPoint: screenPoint) { reach = min(radius, 0.5 * onScreen) }
                if distance <= reach, distance < (best?.distance ?? .infinity) { best = (candidate.end, candidate.at, distance) }
            }
            if let best { return .corner(solid: solid, id, best.end, at: best.at) }
            return .edge(solid: solid, id)
        }
    }

    /// A full circle's centre when the pointer is within `min(radius, 0.5 × the circle's on-screen radius)` points of it, the nearest
    /// such centre of `circles`. A centre is its own hover target: a large hole's is far from its rim.
    static func centre(at point: ScreenPoint, among circles: [CircleCentre], screenPoint: (Vector3) -> ScreenPoint?,
                       radius: Double = 10) -> MeasurePick? {
        var best: (circle: CircleCentre, distance: Double)?
        for circle in circles {
            guard let screen = screenPoint(circle.centre), let onScreen = screenRadius(of: circle.curve, screenPoint: screenPoint)
            else { continue }
            let distance = screen.distance(to: point)
            if distance <= min(radius, 0.5 * onScreen), distance < (best?.distance ?? .infinity) { best = (circle, distance) }
        }
        return best.map { .corner(solid: $0.circle.solid, $0.circle.edge, .centre, at: $0.circle.centre) }
    }

    /// The full circles of `topology`, with the centres snapping can offer.
    static func circleCentres(of topology: Topology, solid: Int) -> [CircleCentre] {
        topology.edges.compactMap { edge in
            guard let curve = edge.curve, case let .circle(center, _, _, _, sweep) = curve, abs(sweep) >= 2 * Double.pi - 1e-9
            else { return nil }
            return CircleCentre(solid: solid, edge: edge.id, centre: center, curve: curve)
        }
    }

    /// The circle's radius on screen: the larger of the distances from its centre to two points a quarter turn apart.
    private static func screenRadius(of curve: EdgeCurve, screenPoint: (Vector3) -> ScreenPoint?) -> Double? {
        guard case let .circle(center, axis, _, start, _) = curve, let middle = screenPoint(center),
              let first = screenPoint(start) else { return nil }
        var result = middle.distance(to: first)
        if let normal = axis.normalized, let across = screenPoint(center + normal.cross(start - center)) {
            result = max(result, middle.distance(to: across))
        }
        return result
    }

    /// What an edge offers to snap to: its ends, or a full circle's centre.
    static func ends(of id: EdgeID, topology: Topology?, mesh: DisplayMesh?) -> [(end: CornerEnd, at: Vector3)] {
        let curve = topology?.edge(id)?.curve
        if case let .circle(center, _, _, _, sweep)? = curve, abs(sweep) >= 2 * Double.pi - 1e-9 { return [(.centre, center)] }
        if let points = curve?.ends, points.count == 2 { return [(.start, points[0]), (.end, points[1])] }
        guard let line = mesh?.edgePolylines[id], let first = line.first, let last = line.last else { return [] }
        return [(.start, first), (.end, last)]
    }
}

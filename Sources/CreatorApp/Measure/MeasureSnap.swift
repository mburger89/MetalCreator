import Foundation
import CreatorGeometry
import CreatorKernel
import CreatorViewport

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
                let distance = ((screen.x - point.x) * (screen.x - point.x) + (screen.y - point.y) * (screen.y - point.y)).squareRoot()
                if distance <= radius, distance < (best?.distance ?? .infinity) { best = (candidate.end, candidate.at, distance) }
            }
            if let best { return .corner(solid: solid, id, best.end, at: best.at) }
            return .edge(solid: solid, id)
        }
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

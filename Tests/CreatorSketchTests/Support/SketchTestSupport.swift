// Test fixture file: shared helpers and sketch builders for CreatorSketchTests (several helpers by design).
import CreatorGeometry
@testable import CreatorSketch

func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-7) -> Bool { abs(a - b) <= tolerance }
func isClose(_ a: Vector2, _ b: Vector2, tolerance: Double = 1e-7) -> Bool { (a - b).length <= tolerance }
/// For "which solution did it pick" checks: LM's damped steps may slide a little along freedom
/// the constraints leave, so positions along a free direction are only near the minimal move.
func isNear(_ a: Vector2, _ b: Vector2) -> Bool { (a - b).length <= 1e-3 }

extension Sketch {
    /// The (start, end) point IDs of a line.
    func ends(_ line: SketchEntityID) -> (SketchEntityID, SketchEntityID) {
        guard case .line(let start, let end) = entities[line]?.kind else { preconditionFailure("not a line") }
        return (start, end)
    }

    /// The (center, start, end) point IDs of an arc.
    func arcPoints(_ arc: SketchEntityID) -> (SketchEntityID, SketchEntityID, SketchEntityID) {
        guard case .arc(let center, let start, let end) = entities[arc]?.kind else { preconditionFailure("not an arc") }
        return (center, start, end)
    }

    /// The center point ID of a circle.
    func centerOf(_ circle: SketchEntityID) -> SketchEntityID {
        guard case .circle(let center, _) = entities[circle]?.kind else { preconditionFailure("not a circle") }
        return center
    }

    /// The entities of one kind, in ID order.
    func ids(ofKind name: String) -> [SketchEntityID] {
        entityIDs.filter { entities[$0].map { Sketch.kindName($0.kind) == name } ?? false }
    }
}

/// A closed polyline through `corners`, counter-clockwise if they are. Returns the lines in order;
/// line i runs from corner i to corner i + 1.
@discardableResult
func addPolygon(_ sketch: inout Sketch, _ corners: [Vector2], isConstruction: Bool = false) -> [SketchEntityID] {
    let points = corners.map { sketch.addPoint($0) }
    return points.indices.map { sketch.addLine(from: points[$0], to: points[($0 + 1) % points.count], isConstruction: isConstruction) }
}

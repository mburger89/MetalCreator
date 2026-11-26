import CreatorGeometry
import Foundation

/// A stepped cutting line on a drawing view (DR-3 R2): `points` in the parent view's model plane (millimetres, `frame.place`
/// coordinates), `viewing` the unit direction the section looks toward, square to the first segment. Segments alternate
/// cut, step, cut, ...: the cuts run the same way, the steps square to them.
public struct SectionCutter: Hashable, Sendable, Codable {
    /// The parent view's frame.
    public var frame: ProjectionFrame
    public var points: [Vector2]
    public var viewing: Vector2

    public init(frame: ProjectionFrame, points: [Vector2], viewing: Vector2) {
        self.frame = frame
        self.points = points
        self.viewing = viewing
    }

    /// The tool node every cut is tagged with (R4); never a graph node's id.
    public static let toolNode = NodeID(rawValue: UUID(uuidString: "5EC7C0DE-0D30-4000-8000-000000000001") ?? UUID())

    private static let tolerance = 1e-9

    private func segment(_ k: Int) -> Vector2 { points[k + 1] - points[k] }

    /// The first segment's unit direction (zero when there is none).
    public var direction: Vector2 {
        guard points.count >= 2 else { return .zero }
        let first = segment(0)
        let length = first.length
        return length > 0 ? first * (1 / length) : .zero
    }

    /// The indices of the cuts: 0, 2, 4, ... below the segment count.
    public var cutIndices: [Int] {
        points.count >= 2 ? Array(stride(from: 0, to: points.count - 1, by: 2)) : []
    }

    public func validate() throws(KernelError) {
        guard points.count >= 2 else { throw KernelError.invalidInput("A cutting line needs at least two points.") }
        let count = points.count - 1
        for k in 0..<count where segment(k).length < 1e-6 {
            throw KernelError.invalidInput("A cutting line's points must be apart.")
        }
        let first = segment(0)
        let firstLength = first.length
        let alternates = "A stepped cutting line alternates cuts and steps at right angles, starting and ending with a cut."
        guard count % 2 == 1 else { throw KernelError.invalidInput(alternates) }
        for k in stride(from: 1, to: count, by: 2) {
            let step = segment(k)
            guard abs(first.x * step.x + first.y * step.y) <= Self.tolerance * firstLength * step.length else {
                throw KernelError.invalidInput(alternates)
            }
        }
        for k in stride(from: 2, to: count, by: 2) {
            let cut = segment(k)
            let parallel = abs(first.x * cut.y - first.y * cut.x) <= Self.tolerance * firstLength * cut.length
            guard parallel, first.x * cut.x + first.y * cut.y > 0 else {
                throw KernelError.invalidInput("Every cut of a stepped cutting line runs the same way as the first.")
            }
        }
        let t = direction
        guard abs(viewing.length - 1) <= Self.tolerance, abs(viewing.x * t.x + viewing.y * t.y) <= Self.tolerance else {
            throw KernelError.invalidInput("The cutting line's view direction must be square to it.")
        }
    }

    /// The region the cut removes, in plane coordinates: the line, extended `reach` past its first and last points, and its
    /// far side `reach` away from `viewing`. Vertex k to k + 1 is the line's segment k for every k below its segment count.
    public func removedPolygon(reach: Double) -> [Vector2] {
        guard points.count >= 2, let last = points.last else { return [] }
        let t = direction
        let q0 = points[0] - t * reach
        let qn = last + t * reach
        var polygon = [q0]
        if points.count > 2 { polygon.append(contentsOf: points[1..<(points.count - 1)]) }
        polygon.append(qn)
        polygon.append(qn - viewing * reach)
        polygon.append(q0 - viewing * reach)
        return polygon
    }
}

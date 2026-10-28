import CreatorGeometry
import CreatorGraph
import Foundation

/// The dimensions the layouts declare on their first row, column or ring (spec §3.1). A layout with fewer than two
/// placements along a direction has nothing to measure there, and a gap of zero is not drawn.
enum LayoutDimensions {
    private static let tiny = 1e-9

    private static func linear(_ target: DimensionTarget, _ quantity: DimensionQuantity, value: Double, from: Vector3, to: Vector3,
                               side: Vector3) -> DimensionSpec? {
        guard let direction = (to - from).normalized, value.isFinite else { return nil }
        return DimensionSpec(target, .linear(from: from, to: to, direction: direction, side: side, placement: .standoff), quantity,
                             value: value)
    }

    /// Linear: the spacing from the first placement to the second (or the whole length, when one is given) and the count
    /// across the row on the opposite side.
    static func linear(origins: [Vector3], direction: Vector3, spacing: Double?, length: Double?, count: Int) -> [DimensionSpec] {
        guard count >= 2, let first = origins.first, let last = origins.last, (last - first).length > tiny else { return [] }
        let side = DimensionSpecs.perpendicular(to: direction)
        var specs: [DimensionSpec] = []
        if let length {
            specs += linear(.input("length"), .length, value: length, from: first, to: last, side: side).map { [$0] } ?? []
        } else if let spacing, origins.count > 1 {
            specs += linear(.input("spacing"), .length, value: spacing, from: first, to: origins[1], side: side).map { [$0] } ?? []
        }
        specs += linear(.input("count"), .count, value: Double(count), from: first, to: last, side: -side).map { [$0] } ?? []
        return specs
    }

    /// Grid: both spacings from the first placement, and the counts across the first row and the first column.
    static func grid(plane: Plane, first: Vector3, spacing: Vector2, counts: (x: Int, y: Int)) -> [DimensionSpec] {
        let (x, y) = (plane.xAxis, plane.yAxis)
        var specs: [DimensionSpec?] = []
        if counts.x >= 2, spacing.x > tiny {
            specs.append(linear(.input("spacingX"), .length, value: spacing.x, from: first, to: first + x * spacing.x, side: -y))
            let end = first + x * (Double(counts.x - 1) * spacing.x)
            specs.append(linear(.input("countX"), .count, value: Double(counts.x), from: first, to: end, side: y))
        }
        if counts.y >= 2, spacing.y > tiny {
            specs.append(linear(.input("spacingY"), .length, value: spacing.y, from: first, to: first + y * spacing.y, side: -x))
            let end = first + y * (Double(counts.y - 1) * spacing.y)
            specs.append(linear(.input("countY"), .count, value: Double(counts.y), from: first, to: end, side: x))
        }
        return specs.compactMap { $0 }
    }

    /// Circular, first ring: the radius to the first placement, the count as a leader toward the second, and a sweep
    /// short of a full turn as the angle from the first placement to the last.
    static func circular(centre: Vector3, axis: Vector3, radius: Double, sweep: Double, origins: [Vector3]) -> [DimensionSpec] {
        guard radius.isFinite, radius > tiny, let first = origins.first, let toward = (first - centre).normalized else { return [] }
        func radial(_ direction: Vector3) -> DimensionGeometry {
            .radial(center: centre, radius: radius, normal: axis, toward: direction, placement: .standoff)
        }
        var specs = [DimensionSpec(.input("radius"), radial(toward), .radius, value: radius)]
        guard origins.count >= 2, let last = origins.last else { return specs }
        if let second = (origins[1] - centre).normalized {
            specs.append(DimensionSpec(.input("count"), radial(second), .count, value: Double(origins.count)))
        }
        if abs(sweep) < 360 - tiny, sweep.isFinite {
            let arc = DimensionGeometry.angular(vertex: centre, first: first, second: last, normal: axis, placement: .standoff)
            specs.append(DimensionSpec(.input("sweep"), arc, .angle, value: sweep))
        }
        return specs
    }
}

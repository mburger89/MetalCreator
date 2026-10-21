import CreatorGeometry
import CreatorImplicit
import CreatorKernel
import Foundation

/// Face charts made from a surface written as a formula, through the same assembler the kernel's answers go through: what a kernel
/// would say about a whole cylinder's side, or a plane, without one.
enum SyntheticFace {
    /// The box the charts cover.
    static let bounds = BoundingBox(min: Vector3(-26, -26, -14), max: Vector3(26, 26, 14))

    /// The side of a cylinder of `radius` about the Z axis through `axis` (x, y): u is the angle from +X in [0, 2π) as OpenCascade has it,
    /// v the height from the bottom 14 mm below the origin, and the depth the distance from the surface, negative inside.
    static func cylinder(radius: Double = 14, axis: Vector2 = .zero, covering box: BoundingBox = bounds,
                         spacing: Double = 0.6) -> FaceChart {
        let grid = FaceChartGrid(covering: box, spacing: spacing)
        let samples = grid.points.map { point -> FaceSample in
            let (x, y) = (point.x - axis.x, point.y - axis.y)
            let angle = atan2(y, x)
            return FaceSample(u: angle < 0 ? angle + 2 * Double.pi : angle, v: point.z + 14, depth: (x * x + y * y).squareRoot() - radius)
        }
        let facts = FaceParametrization(kind: .cylinder, uMid: Double.pi, vMid: 14, uScale: radius, vScale: 1, uPeriod: 2 * Double.pi)
        return FaceChartAssembler.assemble(grid: grid, facts: facts, samples: samples)
    }

    /// A plane facing +Z at height `height`: u is x, v is y, the depth is the height above it.
    static func plane(height: Double = 0, covering box: BoundingBox = bounds, spacing: Double = 1) -> FaceChart {
        let grid = FaceChartGrid(covering: box, spacing: spacing)
        let samples = grid.points.map { FaceSample(u: $0.x, v: $0.y, depth: $0.z - height) }
        let facts = FaceParametrization(kind: .plane, uMid: 0, vMid: 0, uScale: 1, vScale: 1)
        return FaceChartAssembler.assemble(grid: grid, facts: facts, samples: samples)
    }
}

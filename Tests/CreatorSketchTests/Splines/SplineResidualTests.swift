import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// The joint rows against central differences (the solver never uses finite differences), and a few hand-checked values.
struct SplineResidualTests {
    // Unknowns: p0 (1,2), p1 (7,3), p2 (4,8), p3 (−2,5), then T (3,1) and A (−1,2) of one spline end, T2 (2,−1), A2 (0.5,1.5), r 6.
    static let x: [Double] = [1, 2, 7, 3, 4, 8, -2, 5, 3, 1, -1, 2, 2, -1, 0.5, 1.5, 6]
    static let p0 = PointOperand.unknown(column: 0)
    static let p1 = PointOperand.unknown(column: 2)
    static let p2 = PointOperand.unknown(column: 4)
    static let p3 = PointOperand.unknown(column: 6)
    static let circle = CircleOperand(center: p2, radius: .unknown(column: 16), endpoints: [])
    static let arc = CircleOperand(center: p2, radius: .through(p3), endpoints: [p3, p1])

    static let line = JointSide.line(from: p0, to: p1)
    static let arcStart = JointSide.arc(joint: p3, circle: arc, sense: 1)
    static let arcEnd = JointSide.arc(joint: p1, circle: arc, sense: -1)
    static let first = JointSide.spline(tangent: 8, curvature: 10, reversed: false)
    static let last = JointSide.spline(tangent: 12, curvature: 14, reversed: true)
    static let sides = [line, arcStart, arcEnd, first, last]

    static let equations: [Equation] = {
        var result: [Equation] = []
        for (a, b) in [(first, line), (first, arcStart), (last, arcEnd), (first, last), (last, first), (line, last)] {
            result.append(.jointTangent(a, b, scale: 5))
            result.append(.jointCurvature(a, b, branch: -1, scale: 25))
            result.append(.jointCurvature(a, b, branch: 1, scale: 25))
        }
        return result
    }()

    @Test(arguments: equations)
    func analyticJacobianMatchesCentralDifferences(_ equation: Equation) {
        let rows = equation.rows(Self.x)
        #expect(rows.count == equation.rowCount)
        let h = 1e-6
        for (index, row) in rows.enumerated() {
            var analytic = Array(repeating: 0.0, count: Self.x.count)
            for entry in row.entries { analytic[entry.column] += entry.value }
            for column in Self.x.indices {
                var plus = Self.x
                var minus = Self.x
                plus[column] += h
                minus[column] -= h
                let numeric = (equation.rows(plus)[index].value - equation.rows(minus)[index].value) / (2 * h)
                #expect(isClose(analytic[column], numeric, tolerance: 1e-5), "row \(index), column \(column)")
            }
        }
    }

    @Test func columnsListEveryHandleColumn() {
        let columns = Equation.jointCurvature(Self.first, Self.last, branch: -1, scale: 1).columns
        #expect(Set(columns) == [8, 9, 10, 11, 12, 13, 14, 15])
    }

    @Test func curvatureOfASplineEndIsTCrossAOverSpeedCubed() {
        // T = (3,1), A = (−1,2): T × A = 7; |T|³ = 10√10.
        let expected = 7 / (10 * 10.0.squareRoot())
        #expect(isClose(Self.first.curvature(Self.x).value, expected, tolerance: 1e-12))
        // Walking the other way round the last point flips the sign: T2 = (2,−1), A2 = (0.5,1.5): 3 + 0.5 = 3.5; |T2|³ = 5√5.
        #expect(isClose(Self.last.curvature(Self.x).value, -3.5 / (5 * 5.0.squareRoot()), tolerance: 1e-12))
    }

    @Test func anArcsCurvatureFollowsItsTurningSense() {
        let radius = (Vector2(-2, 5) - Vector2(4, 8)).length
        #expect(isClose(Self.arcStart.curvature(Self.x).value, 1 / radius, tolerance: 1e-12))
        #expect(isClose(Self.arcEnd.curvature(Self.x).value, -1 / radius, tolerance: 1e-12))
        #expect(Self.line.curvature(Self.x).value == 0)
    }

    @Test func tangentIsZeroForParallelOutgoingDirections() {
        var x = Self.x
        x[8] = 6
        x[9] = 1  // T = (6, 1) = the line's direction (6, 1)
        let rows = Equation.jointTangent(Self.first, Self.line, scale: 3).rows(x)
        #expect(isClose(rows[0].value, 0, tolerance: 1e-12))
    }
}

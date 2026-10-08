import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Driving angles are directed (final review): each one keeps the sense it was created with, so
/// a typed obtuse value is met as typed and a sweep never folds back at 90°.
struct DirectedAngleTests {
    /// A fixed base line along +x from the origin and a second line from the origin, drawn at
    /// `degrees`, with an angle dimension of `|degrees|` between them.
    struct Vee {
        var sketch = Sketch()
        let base: SketchEntityID
        let arm: SketchEntityID
        let angle: DimensionID

        init(degrees: Double) {
            let origin = sketch.addPoint(.zero)
            sketch.add(.fix(origin, at: .zero))
            let baseEnd = sketch.addPoint(Vector2(10, 0))
            sketch.add(.fix(baseEnd, at: Vector2(10, 0)))
            base = sketch.addLine(from: origin, to: baseEnd)
            let radians = degrees * .pi / 180
            arm = sketch.addLine(from: origin, to: sketch.addPoint(Vector2(cos(radians), sin(radians)) * 10))
            angle = sketch.addDimension(.angle(base, arm), value: abs(degrees))
        }

        /// The arm's polar angle in degrees after solving with the dimension at `value`.
        mutating func solve(at value: Double) throws -> Double {
            sketch.dimensions[angle]?.value = value
            let solution = SketchSolver.solve(sketch)
            try #require(solution.status.isUsable, "status \(solution.status) at \(value)°")
            sketch.remember(solution)
            let end = try #require(solution.points[sketch.ends(arm).1])
            return atan2(end.y, end.x) * 180 / .pi
        }
    }

    @Test func anAcuteVeeOpensToATypedObtuseAngle() throws {
        var vee = Vee(degrees: 60)
        #expect(isClose(try vee.solve(at: 60), 60, tolerance: 1e-6))
        #expect(isClose(try vee.solve(at: 120), 120, tolerance: 1e-6))
    }

    @Test func aClockwiseSweepFrom10To170NeverFoldsBack() throws {
        var vee = Vee(degrees: -10)
        for value in stride(from: 10.0, through: 170, by: 1) {
            let measured = try vee.solve(at: value)
            #expect(isClose(measured, -value, tolerance: 1e-6), "at \(value)° the arm is at \(measured)°")
        }
    }

    @Test func aCounterClockwiseSweepFrom10To170FollowsTheValue() throws {
        var vee = Vee(degrees: 10)
        for value in stride(from: 10.0, through: 170, by: 1) {
            let measured = try vee.solve(at: value)
            #expect(isClose(measured, value, tolerance: 1e-6), "at \(value)° the arm is at \(measured)°")
        }
    }

    /// The sense is chosen once, from the geometry at creation, and stored with the dimension.
    @Test func theSenseIsStoredWhenTheDimensionIsCreated() throws {
        let clockwise = Vee(degrees: -10)
        let counterClockwise = Vee(degrees: 10)
        #expect(clockwise.sketch.dimensions[clockwise.angle]?.angleSense == AngleSense(isClockwise: true, reversesSecond: false))
        #expect(counterClockwise.sketch.dimensions[counterClockwise.angle]?.angleSense
            == AngleSense(isClockwise: false, reversesSecond: false))
    }

    /// A dimension made without a sense (an older file, or built by hand) takes the one nearest
    /// its first solve, and `remember` stores it from then on.
    @Test func aDimensionWithoutASenseKeepsTheOneItFirstSolvedWith() throws {
        var vee = Vee(degrees: -10)
        vee.sketch.dimensions[vee.angle]?.angleSense = nil
        #expect(isClose(try vee.solve(at: 10), -10, tolerance: 1e-6))
        #expect(vee.sketch.dimensions[vee.angle]?.angleSense == AngleSense(isClockwise: true, reversesSecond: false))
        #expect(isClose(try vee.solve(at: 120), -120, tolerance: 1e-6))
    }

    /// A line drawn away from the vertex measures the angle to its reversed direction.
    @Test func aBackwardsLineKeepsItsSupplementarySense() throws {
        var sketch = Sketch()
        let origin = sketch.addPoint(.zero)
        sketch.add(.fix(origin, at: .zero))
        let baseEnd = sketch.addPoint(Vector2(10, 0))
        sketch.add(.fix(baseEnd, at: Vector2(10, 0)))
        let base = sketch.addLine(from: origin, to: baseEnd)
        let tip = sketch.addPoint(Vector2(cos(.pi / 3), sin(.pi / 3)) * 10)
        let arm = sketch.addLine(from: tip, to: origin)
        let angle = sketch.addDimension(.angle(base, arm), value: 60)
        #expect(sketch.dimensions[angle]?.angleSense == AngleSense(isClockwise: false, reversesSecond: true))
        sketch.dimensions[angle]?.value = 120
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status.isUsable)
        let solvedTip = try #require(solution.points[tip])
        #expect(isClose(atan2(solvedTip.y, solvedTip.x) * 180 / .pi, 120, tolerance: 1e-6))
    }
}

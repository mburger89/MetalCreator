import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

struct MirrorPatternTests {
    @Test func mirroringATriangleAddsSymmetricPoints() throws {
        var sketch = Sketch()
        let axis = sketch.addLine(Vector2(0, -10), Vector2(0, 10), isConstruction: true)
        let lines = addPolygon(&sketch, [Vector2(2, 0), Vector2(6, 0), Vector2(4, 3)])
        let edit = try SketchCommands.mirror(sketch, entities: lines, about: axis)
        let mirrored = edit.sketch
        #expect(edit.description == "Mirror 3 entities")
        #expect(mirrored.ids(ofKind: "Line").count == 7)
        let symmetric = mirrored.constraintList.filter { if case .symmetric = $0 { true } else { false } }
        #expect(symmetric.count == 3)
        let copies = mirrored.ids(ofKind: "Point").suffix(3).compactMap { mirrored.position(of: $0) }
        #expect(zip(copies, [Vector2(-2, 0), Vector2(-6, 0), Vector2(-4, 3)]).allSatisfy { isClose($0, $1) })
        try requireSolvesInPlace(mirrored)
    }

    @Test func pointsOnTheAxisAreShared() throws {
        var sketch = Sketch()
        let axis = sketch.addLine(Vector2(0, -10), Vector2(0, 10))
        let line = sketch.addLine(.zero, Vector2(5, 5))
        let mirrored = try SketchCommands.mirror(sketch, entities: [line, axis], about: axis).sketch
        let copy = try #require(mirrored.ids(ofKind: "Line").last)
        #expect(mirrored.ends(copy).0 == sketch.ends(line).0)
        // One symmetric pair, and the shared point held on the axis.
        #expect(mirrored.constraintList == [.symmetric(sketch.ends(line).1, mirrored.ends(copy).1, about: axis),
                                            .pointOn(point: sketch.ends(line).0, curve: axis),
        ])
        try requireSolvesInPlace(mirrored)
    }

    /// The shared point stays on the axis when dragged, so the mirror stays symmetric.
    @Test func dragsKeepAMirrorSymmetric() throws {
        var sketch = Sketch()
        let bottom = sketch.addPoint(Vector2(0, -10))
        sketch.add(.fix(bottom, at: Vector2(0, -10)))
        let top = sketch.addPoint(Vector2(0, 10))
        sketch.add(.fix(top, at: Vector2(0, 10)))
        let axis = sketch.addLine(from: bottom, to: top)
        let line = sketch.addLine(.zero, Vector2(5, 5))
        let mirrored = try SketchCommands.mirror(sketch, entities: [line], about: axis).sketch
        let copy = try #require(mirrored.ids(ofKind: "Line").last)
        let (shared, end) = mirrored.ends(line)
        let solution = SketchSolver.solve(mirrored, dragging: [shared: Vector2(3, 0)])
        try #require(solution.status.isUsable, "status \(solution.status)")
        let sharedPosition = try #require(solution.points[shared])
        #expect(abs(sharedPosition.x) <= 1e-7)
        let original = try #require(solution.points[end])
        let reflected = try #require(solution.points[mirrored.ends(copy).1])
        #expect(isClose(reflected, Vector2(-original.x, original.y)))
    }

    /// A point already held on the axis gets no second, redundant point-on.
    @Test func pointsAlreadyOnTheAxisAddNothing() throws {
        var sketch = Sketch()
        let axis = sketch.addLine(Vector2(0, -10), Vector2(0, 10))
        let (axisStart, _) = sketch.ends(axis)
        let line = sketch.addLine(from: axisStart, to: sketch.addPoint(Vector2(5, 5)))
        let onAxis = sketch.addPoint(.zero)
        sketch.add(.pointOn(point: onAxis, curve: axis))
        let other = sketch.addLine(from: onAxis, to: sketch.addPoint(Vector2(4, 1)))
        let mirrored = try SketchCommands.mirror(sketch, entities: [line, other], about: axis).sketch
        #expect(mirrored.constraintList.filter { if case .pointOn = $0 { true } else { false } }.count == 1)
        #expect(SketchSolver.solve(mirrored).status.isUsable)
    }

    /// A shared point already held on the axis by other constraints (here a fix, with the axis
    /// fixed too) gets no point-on: it would be dependent and turn the sketch over-constrained.
    @Test func aFixedSharedPointOnAFixedAxisAddsNoPointOn() throws {
        var sketch = Sketch()
        let bottom = sketch.addPoint(Vector2(0, -10))
        sketch.add(.fix(bottom, at: Vector2(0, -10)))
        let top = sketch.addPoint(Vector2(0, 10))
        sketch.add(.fix(top, at: Vector2(0, 10)))
        let axis = sketch.addLine(from: bottom, to: top)
        let line = sketch.addLine(.zero, Vector2(5, 5))
        sketch.add(.fix(sketch.ends(line).0, at: .zero))
        #expect(SketchSolver.solve(sketch).status == .underConstrained(dof: 2))
        let mirrored = try SketchCommands.mirror(sketch, entities: [line], about: axis).sketch
        #expect(!mirrored.constraintList.contains { if case .pointOn = $0 { true } else { false } })
        #expect(SketchSolver.solve(mirrored).status == .underConstrained(dof: 2))
    }

    /// A shared point coincident with a point held on the axis is held there already.
    @Test func aSharedPointCoincidentWithAPointOnTheAxisAddsNoPointOn() throws {
        var sketch = Sketch()
        let axis = sketch.addLine(Vector2(0, -10), Vector2(0, 10))
        let onAxis = sketch.addPoint(.zero)
        sketch.add(.pointOn(point: onAxis, curve: axis))
        let line = sketch.addLine(.zero, Vector2(5, 5))
        sketch.add(.coincident(onAxis, sketch.ends(line).0))
        let mirrored = try SketchCommands.mirror(sketch, entities: [line], about: axis).sketch
        #expect(mirrored.constraintList.filter { if case .pointOn = $0 { true } else { false } }.count == 1)
        let status = SketchSolver.solve(mirrored).status
        #expect(status.isUsable, "status \(status)")
    }

    @Test func aMirroredArcRunsCounterClockwiseAndStaysFullyConstrained() throws {
        var sketch = Sketch()
        let axis = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(Vector2(0, -10), Vector2(0, 10))))))
        let points = [Vector2(5, 0), Vector2(8, 0), Vector2(5, 3)].map { position in
            let point = sketch.addPoint(position)
            sketch.add(.fix(point, at: position))
            return point
        }
        let arc = sketch.addArc(center: points[0], start: points[1], end: points[2])
        let mirrored = try SketchCommands.mirror(sketch, entities: [arc], about: axis).sketch
        let copy = try #require(mirrored.ids(ofKind: "Arc").last)
        let (center, start, end) = mirrored.arcPoints(copy)
        #expect(isClose(try #require(mirrored.position(of: center)), Vector2(-5, 0)))
        #expect(isClose(try #require(mirrored.position(of: start)), Vector2(-5, 3)))
        #expect(isClose(try #require(mirrored.position(of: end)), Vector2(-8, 0)))
        #expect(try requireSolvesInPlace(mirrored).status == .solved)
    }

    @Test func mirroredCirclesKeepEqualRadii() throws {
        var sketch = Sketch()
        let axis = sketch.addLine(Vector2(0, -10), Vector2(0, 10))
        let circle = sketch.addCircle(center: Vector2(4, 4), radius: 2)
        let mirrored = try SketchCommands.mirror(sketch, entities: [circle], about: axis).sketch
        let copy = try #require(mirrored.ids(ofKind: "Circle").last)
        #expect(mirrored.constraintList.contains(.equal(circle, copy)))
        #expect(mirrored.radius(of: copy) == 2)
        try requireSolvesInPlace(mirrored)
    }

    @Test func linearPatternSpacesCopiesWithDistanceDimensions() throws {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: .zero, radius: 2)
        let edit = try SketchCommands.linearPattern(sketch, entities: [circle], direction: Vector2(3, 0), spacing: 10, count: 3)
        let patterned = edit.sketch
        #expect(edit.description == "Linear pattern of 1 entity (×3)")
        let circles = patterned.ids(ofKind: "Circle")
        try #require(circles.count == 3)
        let centers = circles.compactMap { patterned.position(of: patterned.centerOf($0)) }
        #expect(zip(centers, [Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)]).allSatisfy { isClose($0, $1) })
        // Two equal radii, plus the second connector held parallel and equal to the first.
        #expect(patterned.constraintList.filter { if case .equal = $0 { true } else { false } }.count == 3)
        #expect(patterned.constraintList.filter { if case .parallel = $0 { true } else { false } }.count == 1)
        #expect(patterned.constraintList.filter { if case .horizontal = $0 { true } else { false } }.count == 1)
        let distances = patterned.dimensions.values.filter { if case .distance = $0.kind { true } else { false } }
        #expect(distances.map(\.value) == [10])
        try requireSolvesInPlace(patterned)
        #expect(SketchRegions.find(in: patterned).regions.count == 3)
    }

    @Test func circularPatternUsesEqualSpokesAndAngles() throws {
        var sketch = Sketch()
        let pivot = sketch.addPoint(.zero)
        let circle = sketch.addCircle(center: Vector2(10, 0), radius: 1)
        let patterned = try SketchCommands.circularPattern(sketch, entities: [circle], center: pivot, count: 4).sketch
        let circles = patterned.ids(ofKind: "Circle")
        try #require(circles.count == 4)
        let centers = circles.compactMap { patterned.position(of: patterned.centerOf($0)) }
        let expected = [Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0), Vector2(0, -10)]
        #expect(zip(centers, expected).allSatisfy { isClose($0, $1, tolerance: 1e-9) })
        let spokes = patterned.ids(ofKind: "Line")
        #expect(spokes.count == 4)
        #expect(spokes.allSatisfy { patterned.entities[$0]?.isConstruction == true })
        let angles = patterned.dimensions.values.filter { if case .angle = $0.kind { true } else { false } }
        #expect(angles.map(\.value) == [90, 90, 90])
        try requireSolvesInPlace(patterned)
        // Spokes are construction: only the four circles are regions.
        #expect(SketchRegions.find(in: patterned).regions.count == 4)
    }

    /// A pattern holds each copy rigidly, without redundancy or new freedom, so a closed loop
    /// patterned keeps the status it had (spec §10: the result solves).
    @Test(arguments: [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
    func linearPatternsOfClosedLoopsKeepTheirStatus(direction: Vector2) throws {
        let rectangle = ConstrainedRectangle()
        var triangle = Sketch()
        let sides = addPolygon(&triangle, [.zero, Vector2(4, 0), Vector2(2, 3)])
        for (sketch, lines) in [(rectangle.sketch, rectangle.lines), (triangle, sides)] {
            let before = SketchSolver.solve(sketch).status
            let patterned = try SketchCommands.linearPattern(sketch, entities: lines, direction: direction, spacing: 80, count: 3).sketch
            #expect(SketchSolver.solve(patterned).status == before)
        }
        let solved = try SketchCommands.linearPattern(rectangle.sketch, entities: rectangle.lines, direction: direction,
                                                      spacing: 80, count: 3).sketch
        #expect(SketchSolver.solve(solved).status == .solved)
    }

    @Test func circularPatternsOfClosedLoopsKeepTheirStatus() throws {
        var rectangle = ConstrainedRectangle(drawnOffset: 0)
        let rectanglePivot = rectangle.sketch.addPoint(Vector2(-30, -30))
        rectangle.sketch.add(.fix(rectanglePivot, at: Vector2(-30, -30)))
        var triangle = Sketch()
        let sides = addPolygon(&triangle, [.zero, Vector2(4, 0), Vector2(2, 3)])
        let trianglePivot = triangle.addPoint(Vector2(-10, 0))
        triangle.add(.fix(trianglePivot, at: Vector2(-10, 0)))
        let cases = [(rectangle.sketch, rectangle.lines, rectanglePivot), (triangle, sides, trianglePivot)]
        for (sketch, lines, pivot) in cases {
            let before = SketchSolver.solve(sketch).status
            let patterned = try SketchCommands.circularPattern(sketch, entities: lines, center: pivot, count: 3).sketch
            #expect(SketchSolver.solve(patterned).status == before)
            try requireSolvesInPlace(patterned)
        }
        #expect(SketchSolver.solve(cases[0].0).status == .solved)
    }

    @Test func linearCopiesFollowTheOriginalRigidly() throws {
        let rectangle = ConstrainedRectangle(drawnOffset: 0)
        var patterned = try SketchCommands.linearPattern(rectangle.sketch, entities: rectangle.lines,
                                                         direction: Vector2(1, 0), spacing: 80, count: 2).sketch
        patterned.dimensions[rectangle.width]?.value = 70
        let solution = SketchSolver.solve(patterned)
        #expect(solution.status == .solved)
        // The copy's corners are the original's, 80 mm along: still a 70 × 40 rectangle.
        let copied = patterned.ids(ofKind: "Point").filter { !rectangle.sketch.ids(ofKind: "Point").contains($0) }
        let originals = rectangle.lines.map { rectangle.sketch.ends($0).0 }
        for (original, copy) in zip(originals, copied) {
            let expected = try #require(solution.points[original]) + Vector2(80, 0)
            #expect(isClose(try #require(solution.points[copy]), expected))
        }
    }

    @Test func patternsNeedTwoOrMoreInstances() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: .zero, radius: 2)
        #expect(throws: SketchCommandError("A pattern needs at least 2 instances.")) {
            try SketchCommands.linearPattern(sketch, entities: [circle], direction: Vector2(1, 0), spacing: 5, count: 1)
        }
        // The dense solver re-solves every drag frame, so patterns stay at a size it solves interactively.
        #expect(throws: SketchCommandError("A pattern can have at most 100 instances.")) {
            try SketchCommands.linearPattern(sketch, entities: [circle], direction: Vector2(1, 0), spacing: 5, count: 101)
        }
    }
}

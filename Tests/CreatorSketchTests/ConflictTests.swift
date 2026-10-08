import CreatorGeometry
import Testing
@testable import CreatorSketch

/// Over-constrained and refused sketches: minimal conflict sets in plain language (spec §4, §10).
struct ConflictTests {
    @Test func horizontalLineAgainstAnAngleToAProjectedEdge() throws {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 0))))))
        // Two unrelated lines and three dimensions first, so the names match the spec's example.
        for y in [20.0, 30.0] {
            let line = sketch.addLine(Vector2(0, y), Vector2(10, y))
            sketch.addDimension(.length(line), value: 10)
        }
        sketch.addDimension(.length(sketch.ids(ofKind: "Line")[0]), value: 10, isDriving: false)
        let line = sketch.addLine(Vector2(0, 5), Vector2(10, 6))
        let horizontal = sketch.add(.horizontal(line))
        let angle = sketch.addDimension(.angle(edge, line), value: 30)
        let drawn = sketch.position(of: sketch.ends(line).1)

        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .overConstrained(conflicts: [.constraint(horizontal), .dimension(angle)]))
        #expect(solution.conflictMessages == ["Horizontal on Line 3 conflicts with Angle d4 (30°)."])
        #expect(solution.freedom[line] == .conflicting)
        #expect(solution.freedom[edge] == .conflicting)
        // The unsatisfiable component keeps its warm start, for the ghosted last good geometry.
        #expect(solution.points[sketch.ends(line).1] == drawn)
        #expect(solution.status.isUsable == false)
    }

    @Test func redundantParallelOnARectangleIsNamedWithTheConstraintsItRepeats() {
        var rectangle = ConstrainedRectangle()
        let horizontals = rectangle.sketch.constraintIDs.filter {
            if case .horizontal = rectangle.sketch.constraints[$0] { return true }
            return false
        }
        let parallel = rectangle.sketch.add(.parallel(rectangle.lines[0], rectangle.lines[2]))
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.status == .overConstrained(conflicts: horizontals.map(SketchConstraintRef.constraint) + [.constraint(parallel)]))
        #expect(solution.conflictMessages
            == ["Horizontal on Line 1 conflicts with Horizontal on Line 3 and Parallel on Line 1 and Line 3."])
    }

    @Test func impossibleTriangleNamesItsThreeSides() {
        var sketch = Sketch()
        let lines = addPolygon(&sketch, [.zero, Vector2(4, 0), Vector2(2, 3)])
        sketch.add(.fix(sketch.ends(lines[0]).0, at: .zero))
        sketch.add(.horizontal(lines[0]))
        let sides = [3.0, 4, 10].enumerated().map { sketch.addDimension(.length(lines[$0.offset]), value: $0.element) }
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .overConstrained(conflicts: sides.map(SketchConstraintRef.dimension)))
        #expect(solution.conflictMessages == ["Length d1 (3 mm) conflicts with Length d2 (4 mm) and Length d3 (10 mm)."])
    }

    /// A component with two independent conflicts reports one minimal set for each, so fixing
    /// the first never just uncovers the second.
    @Test func independentConflictsInOneComponentAreEachReported() {
        var rectangle = ConstrainedRectangle()
        let wide = rectangle.sketch.addDimension(.length(rectangle.lines[0]), value: 50)
        let tall = rectangle.sketch.addDimension(.length(rectangle.lines[3]), value: 30)
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.status == .overConstrained(conflicts: [.dimension(rectangle.width), .dimension(wide),
                                                               .dimension(rectangle.height), .dimension(tall),
        ]))
        #expect(solution.conflictMessages == ["Length d1 (60 mm) conflicts with Length d3 (50 mm).",
                                              "Length d2 (40 mm) conflicts with Length d4 (30 mm).",
        ])
    }

    @Test func independentRedundanciesInOneComponentAreEachReported() {
        var rectangle = ConstrainedRectangle()
        let parallel = rectangle.sketch.add(.parallel(rectangle.lines[0], rectangle.lines[2]))
        let sideways = rectangle.sketch.add(.parallel(rectangle.lines[1], rectangle.lines[3]))
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.conflictMessages == [
            "Horizontal on Line 1 conflicts with Horizontal on Line 3 and Parallel on Line 1 and Line 3.",
            "Vertical on Line 2 conflicts with Vertical on Line 4 and Parallel on Line 2 and Line 4.",
        ])
        guard case .overConstrained(let conflicts) = solution.status else {
            Issue.record("status \(solution.status)")
            return
        }
        #expect(conflicts.contains(.constraint(parallel)))
        #expect(conflicts.contains(.constraint(sideways)))
    }

    /// A strip of squares in a row, each fully held: the leftmost edge fixed and vertical, every
    /// square's bottom, top and right edges horizontal, horizontal and vertical, every bottom 10 mm.
    static func squareStrip(_ count: Int) -> Sketch {
        var sketch = Sketch()
        var bottom = sketch.addPoint(.zero)
        var top = sketch.addPoint(Vector2(0, 10))
        sketch.add(.fix(bottom, at: .zero))
        let left = sketch.addLine(from: bottom, to: top)
        sketch.add(.vertical(left))
        sketch.addDimension(.length(left), value: 10)
        for i in 1...count {
            let nextBottom = sketch.addPoint(Vector2(Double(i) * 10 + 0.3, 0.2))
            let nextTop = sketch.addPoint(Vector2(Double(i) * 10 - 0.2, 10.1))
            let lower = sketch.addLine(from: bottom, to: nextBottom)
            let upper = sketch.addLine(from: top, to: nextTop)
            sketch.add(.horizontal(lower))
            sketch.add(.horizontal(upper))
            sketch.add(.vertical(sketch.addLine(from: nextBottom, to: nextTop)))
            sketch.addDimension(.length(lower), value: 10)
            (bottom, top) = (nextBottom, nextTop)
        }
        return sketch
    }

    /// Spec §8 re-solves every frame, so a conflict in a mid-sized sketch must not cost one trial
    /// solve per constraint. The search narrows to the refs carrying the misfit first.
    @Test func aConflictInALargeComponentIsNarrowedBeforeFiltering() throws {
        var sketch = Self.squareStrip(12)
        let firstBottom = sketch.ids(ofKind: "Line")[1]
        let conflicting = sketch.addDimension(.length(firstBottom), value: 12)
        let layout = UnknownLayout(sketch)
        let x0 = layout.warmStart(sketch)
        let terms = try TermBuilder(sketch: sketch, layout: layout, x0: x0).build().terms
        let component = try #require(ComponentPartition(terms: terms, layout: layout).components.first)
        let system = ComponentSystem(terms: component.terms, columns: component.columns, base: x0)
        let start = system.local(x0)
        let stalled = LevenbergMarquardt.minimize(system, from: start)
        let search = ConflictSearch.unsatisfiableSets(system, from: start, stalled: stalled.x)
        let original = try #require(sketch.dimensionIDs.first { $0 != conflicting && sketch.dimensions[$0]?.kind == .length(firstBottom) })
        #expect(search.sets == [[.dimension(original), .dimension(conflicting)]])
        #expect(ComponentSolver.refs(of: system).count > 40)
        #expect(search.trialSolves <= 5)
    }

    @Test func constraintOnFixedGeometryOnlyCantBeMet() {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 3))))))
        let horizontal = sketch.add(.horizontal(edge))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .overConstrained(conflicts: [.constraint(horizontal)]))
        #expect(solution.conflictMessages == ["Horizontal on Projected edge 1 can't be met."])
    }

    @Test func negativeLengthIsRefusedInPlainLanguage() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        sketch.addDimension(.length(line), value: -5)
        #expect(SketchSolver.solve(sketch).status == .failed(reason: "Length d1 must be greater than 0 mm, not -5 mm."))
    }

    @Test func outOfRangeAngleIsRefused() {
        var sketch = Sketch()
        let a = sketch.addLine(.zero, Vector2(10, 0))
        let b = sketch.addLine(.zero, Vector2(0, 10))
        sketch.addDimension(.angle(a, b), value: 200)
        #expect(SketchSolver.solve(sketch).status == .failed(reason: "Angle d1 must be between 0° and 180°, not 200°."))
    }

    @Test func wrongKindOfGeometryIsRefused() {
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        let line = sketch.addLine(Vector2(1, 0), Vector2(5, 0))
        sketch.add(.tangent(point, line))
        #expect(SketchSolver.solve(sketch).status
            == .failed(reason: "Tangent on Point 1 and Line 1 needs a line and an arc or circle, or two arcs or circles."))
    }

    @Test func constraintsOnASuspendedProjectionAreSkippedNotDeleted() {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 0)),
                                                                     isSuspended: true))))
        let point = sketch.addPoint(Vector2(3, 2))
        let onEdge = sketch.add(.pointOn(point: point, curve: edge))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.suspended == [.constraint(onEdge)])
        #expect(solution.status == .underConstrained(dof: 2))
        #expect(solution.points[point] == Vector2(3, 2))
        #expect(sketch.constraints[onEdge] != nil)
    }
}

import CreatorGeometry
import Testing
@testable import CreatorSketch

/// What converging means in practice: precise coincidences and idempotent re-solves.
struct ConvergenceTests {
    @Test func reSolvingASolvedSketchMovesNothing() {
        // The editor re-solves every frame; a solved sketch must not creep.
        var slot = ClassicSketchTests.Slot(length: 27, radius: 3)
        slot.sketch.dimensions = slot.sketch.dimensions.filter { $0.key != slot.length }
        let first = SketchSolver.solve(slot.sketch)
        slot.sketch.remember(first)
        var current = first
        for _ in 0..<5 {
            current = SketchSolver.solve(slot.sketch)
            slot.sketch.remember(current)
        }
        #expect(current.points == first.points)
        #expect(current.status == .underConstrained(dof: 1))
    }

    @Test func solvedCoincidentPointsAgreeToRoundOff() throws {
        // Separate corner points held by coincident constraints, with nonlinear lengths: the
        // converged solve is polished far inside the regions' 1e-9 mm merge tolerance.
        var sketch = Sketch()
        let corners = [Vector2(0, 0), Vector2(30, 0), Vector2(18, 20)]
        let lines = (0..<3).map { i in
            let gap = Vector2(0.3 * Double(i + 1), -0.4 * Double(i))
            return sketch.addLine(corners[i] + gap, corners[(i + 1) % 3] - gap)
        }
        for i in 0..<3 { sketch.add(.coincident(sketch.ends(lines[i]).1, sketch.ends(lines[(i + 1) % 3]).0)) }
        sketch.add(.fix(sketch.ends(lines[0]).0, at: .zero))
        for (line, value) in zip(lines, [31.7, 24.3, 25]) { sketch.addDimension(.length(line), value: value) }
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status.isUsable)
        for i in 0..<3 {
            let a = try #require(solution.points[sketch.ends(lines[i]).1])
            let b = try #require(solution.points[sketch.ends(lines[(i + 1) % 3]).0])
            #expect((a - b).length < 1e-12)
        }
    }

    @Test func anEmptySketchIsSolved() {
        let solution = SketchSolver.solve(Sketch())
        #expect(solution.status == .solved)
        #expect(solution.points.isEmpty)
        #expect(solution.conflictMessages.isEmpty)
    }
}

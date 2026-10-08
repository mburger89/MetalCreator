import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Drag mode re-solves every frame (spec §8), so its pull towards an unreachable target must
/// stop once it stalls instead of running LM's full 200 iterations (final review).
struct DragCostTests {
    /// The hard system and the drag term of the component a drag of `point` to `target` touches.
    func dragSystem(_ sketch: Sketch, dragging point: SketchEntityID, to target: Vector2) throws
        -> (system: ComponentSystem, drag: SolverTerm, start: [Double]) {
        let layout = UnknownLayout(sketch)
        let x0 = layout.warmStart(sketch)
        let terms = try TermBuilder(sketch: sketch, layout: layout, x0: x0).build().terms
        let column = try #require(layout.pointColumns[point])
        let drag = SolverTerm(role: .drag, equation: .target(.unknown(column: column), target))
        let partition = ComponentPartition(terms: terms + [drag], layout: layout)
        let component = try #require(partition.components.first { $0.terms.contains(drag) })
        let system = ComponentSystem(terms: component.terms.filter { $0.role != .drag }, columns: component.columns, base: x0)
        return (system, drag, system.local(x0))
    }

    @Test func pullingAFullyConstrainedCornerStopsWhenItStalls() throws {
        var rectangle = ConstrainedRectangle()
        rectangle.sketch.remember(SketchSolver.solve(rectangle.sketch))
        let corner = rectangle.sketch.ends(rectangle.lines[1]).1
        let (system, drag, start) = try dragSystem(rectangle.sketch, dragging: corner, to: Vector2(500, 300))
        // The pull stops on the stall, before its cap and before plain LM would.
        let unbounded = LevenbergMarquardt.minimize(system.adding([drag]), from: start)
        let pulled = ComponentSolver.pull(system, [drag], from: start)
        #expect(pulled.iterations < ComponentSolver.pullIterationLimit)
        #expect(pulled.iterations < unbounded.iterations)
        let solution = SketchSolver.solve(rectangle.sketch, dragging: [corner: Vector2(500, 300)])
        #expect(solution.status == .solved)
        #expect(isClose(try #require(solution.points[corner]), Vector2(60, 40), tolerance: 1e-6))
    }

    /// On a patterned rectangle the pull is capped however far it still has to go.
    @Test func pullingAPatternedRectangleIsCapped() throws {
        let rectangle = ConstrainedRectangle()
        var patterned = try SketchCommands.linearPattern(rectangle.sketch, entities: rectangle.lines, direction: Vector2(1, 0),
                                                         spacing: 80, count: 2).sketch
        patterned.remember(SketchSolver.solve(patterned))
        let last = try #require(patterned.ids(ofKind: "Point").last)
        let (system, drag, start) = try dragSystem(patterned, dragging: last, to: Vector2(5000, 50))
        // Unbounded, LM spends every iteration on the stalled fit.
        #expect(LevenbergMarquardt.minimize(system.adding([drag]), from: start).iterations == LevenbergMarquardt.iterationLimit)
        #expect(ComponentSolver.pull(system, [drag], from: start).iterations <= ComponentSolver.pullIterationLimit)
        #expect(SketchSolver.solve(patterned, dragging: [last: Vector2(5000, 50)]).status == .solved)
    }
}

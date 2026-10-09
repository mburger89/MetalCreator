import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Selecting (additive clicks, points before curves), the constraint buttons on the selection, Delete, and dragging
/// a point with the live solve (sketcher spec §8).
@MainActor
struct SelectionAndConstraintTests {
    func makeModel(_ sketch: Sketch) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.select)
        return (model, RecordingHost(model))
    }

    @Test func clicksToggleTheSelectionAndPointsWinOverTheirCurves() {
        let rectangle = RectangleSketch()
        let (model, _) = makeModel(rectangle.sketch)
        model.click(at: Vector2(30, 0.5), tolerance: 1, modifiers: [])
        #expect(model.selection == [rectangle.lines[0]])
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(model.selection == [rectangle.lines[0], rectangle.corners[0]], "a corner, not the lines through it")
        model.click(at: Vector2(30, 0.5), tolerance: 1, modifiers: [])
        #expect(model.selection == [rectangle.corners[0]], "a second click deselects")
        model.click(at: Vector2(30, 20), tolerance: 1, modifiers: [])
        #expect(model.selection.isEmpty, "a click on nothing clears it")
    }

    @Test func constraintButtonsFollowTheSelectionsShape() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, _) = makeModel(rectangle.sketch)
        model.selection = [rectangle.lines[0], rectangle.lines[1]]
        #expect(Set(model.availableConstraints) == [.parallel, .perpendicular, .equal])
        model.selection = [rectangle.corners[0]]
        #expect(model.availableConstraints == [.fix])
        model.selection = [rectangle.corners[0], rectangle.corners[2], rectangle.lines[0]]
        #expect(model.availableConstraints == [.symmetric])
    }

    @Test func aConstraintIsOneStepAndClearsTheSelection() throws {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch)
        model.selection = [rectangle.lines[0], rectangle.lines[1]]
        model.addConstraint(.equal)
        #expect(host.commits.map(\.description) == ["Equal"])
        #expect(model.selection.isEmpty)
        #expect(model.solution.degreesOfFreedom == 1, "equal sides leave one size free")
        model.addConstraint(.tangent)
        #expect(model.refusal == SketchConstraintKind.tangent.hint, "nothing selected: the button says what to select")
        #expect(host.commits.count == 1)
    }

    @Test func deleteRemovesTheCurveAndItsLonePoints() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        sketch.add(.horizontal(line))
        let (model, host) = makeModel(sketch)
        model.selection = [line]
        model.deleteSelection()
        #expect(model.sketch.entities.isEmpty && model.sketch.constraints.isEmpty)
        #expect(host.commits.map(\.description) == ["Delete"])
    }

    @Test func deleteRefusesToRemoveAnExposedDimension() {
        var rectangle = RectangleSketch()
        rectangle.sketch.dimensions[rectangle.width]?.isExposed = true
        let (model, host) = makeModel(rectangle.sketch)
        model.selection = [rectangle.lines[0]]
        model.deleteSelection()
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "That would remove d1, which is exposed as an input. Stop exposing it first.")
    }

    @Test func draggingAPointSolvesEveryStepAndCommitsOnceOnRelease() throws {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch)
        #expect(model.beginDrag(at: Vector2(60.3, 40.2), tolerance: 1))
        model.drag(to: Vector2(70, 50))
        #expect(host.commits.isEmpty, "downstream evaluation waits for the release")
        let mid = try #require(model.sketch.position(of: rectangle.corners[2]))
        #expect(abs(mid.x - 70) < 1e-3 && abs(mid.y - 50) < 1e-3, "a free corner follows the pointer")
        let bottom = try #require(model.sketch.position(of: rectangle.corners[1]))
        #expect(abs(bottom.x - 70) < 1e-3 && abs(bottom.y) < 1e-6, "the vertical side keeps it vertical")
        model.endDrag(at: Vector2(80, 50))
        #expect(host.commits.map(\.description) == ["Move Point"])
        let fixed = try #require(model.sketch.position(of: rectangle.corners[0]))
        #expect(fixed.length < 1e-9, "the fixed corner stays")
        #expect(!model.beginDrag(at: Vector2(30, 20), tolerance: 1), "a drag on nothing is the viewport's (it orbits)")
    }

    /// Review Focus 2: dragging a point of a sketch whose constraints conflict moves nothing (no drag step is
    /// usable), so the release records no undo step.
    @Test func aDragThatMovesNothingIsNoUndoStep() {
        var rectangle = RectangleSketch()
        rectangle.sketch.add(.vertical(rectangle.lines[0]))
        let (model, host) = makeModel(rectangle.sketch)
        #expect(model.statusIsProblem)
        #expect(model.beginDrag(at: Vector2(60.2, 40.1), tolerance: 1))
        model.drag(to: Vector2(70, 50))
        model.endDrag(at: Vector2(75, 55))
        #expect(host.commits.isEmpty)
        #expect(model.statusIsProblem, "the readout still shows the conflict")
    }
}

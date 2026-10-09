import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The editor's sketch, its live solve and its commits (sketcher spec §8; S4 → S5 handoff: every edit stores the
/// remembered solve as one step).
@MainActor
struct SketchEditorModelTests {
    @Test func loadingSolvesAndRemembersWithoutCommitting() {
        var rectangle = RectangleSketch()
        rectangle.sketch.move(rectangle.corners[2], to: Vector2(70, 45))
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        let host = RecordingHost(model)
        #expect(model.solution.status == .solved)
        #expect(model.sketch.position(of: rectangle.corners[2]) == model.solution.points[rectangle.corners[2]],
                "the shown positions are the solved ones")
        #expect(host.commits.isEmpty, "opening a sketch isn't an edit")
    }

    @Test func aCommitStoresTheRememberedSolveAsOneStep() throws {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        let host = RecordingHost(model)
        var edited = model.sketch
        edited.dimensions[rectangle.width]?.value = 80
        model.commit(edited, "Change d1")
        let commit = try #require(host.commits.first)
        #expect(host.commits.count == 1 && commit.description == "Change d1")
        let corner = try #require(commit.sketch.position(of: rectangle.corners[1]))
        #expect(abs(corner.x - 80) < 1e-6, "the stored sketch warm-starts from the new solve")
        #expect(model.sketch == commit.sketch)
    }

    @Test func anUnusableSolveIsCommittedAsDrawn() throws {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        let host = RecordingHost(model)
        var edited = model.sketch
        edited.add(.vertical(rectangle.lines[0]))
        model.commit(edited, "Vertical")
        #expect(model.statusIsProblem)
        #expect(host.commits.first?.sketch == edited, "a conflicting sketch keeps its warm start")
    }

    @Test func reloadingTheShownSketchChangesNothing() {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        let shown = model.sketch
        model.reload(shown, plane: .xy)
        #expect(model.sketch == shown)
        var undone = RectangleSketch(dimensioned: false).sketch
        undone.move(undone.entityIDs[0], to: Vector2(1, 1))
        model.reload(undone, plane: .xz)
        #expect(model.plane == .xz)
        #expect(model.solution.degreesOfFreedom == 2, "an undo back to an undimensioned rectangle re-solves it")
    }

    @Test func anEmptySketchSaysHowToStartNotFullyConstrained() {
        #expect(SketchEditorModel(sketch: Sketch(), plane: .xy).statusText.hasPrefix("Nothing drawn yet"))
    }

    @Test func theReadoutNamesTheFreedomOrTheProblem() {
        #expect(SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xy).statusText == "Fully constrained")
        #expect(SketchEditorModel(sketch: RectangleSketch(dimensioned: false).sketch, plane: .xy).statusText
            == "2 degrees of freedom")
        var oneShort = RectangleSketch(dimensioned: false).sketch
        oneShort.addDimension(.length(oneShort.entityIDs[4]), value: 60)
        #expect(SketchEditorModel(sketch: oneShort, plane: .xy).statusText == "1 degree of freedom")
        var conflicting = RectangleSketch().sketch
        conflicting.add(.vertical(conflicting.entityIDs[4]))
        let model = SketchEditorModel(sketch: conflicting, plane: .xy)
        #expect(model.statusIsProblem && model.statusText.contains("conflicts with"))
    }
}

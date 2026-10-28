import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// What the sketch editor answers the viewport's value box (spec §4.5, §7): what a box opens with, and the checks a typed
/// value passes before it is one "Change Dimension" step.
@MainActor
struct SketchValueBoxTests {
    func makeModel(units: DocumentUnits = .millimetres) -> (SketchEditorModel, RectangleSketch, RecordingHost) {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        model.units = units
        return (model, rectangle, RecordingHost(model))
    }

    func id(_ dimension: DimensionID) -> OverlayDimensionID { SketchDimensionDrawing.overlayID(dimension) }

    @Test func aDrivingDimensionOpensWithItsExactValue() {
        let (model, rectangle, _) = makeModel()
        #expect(model.valueBoxContent(for: id(rectangle.width)) == DimensionValueBoxContent(text: "60"))
        let (inches, other, _) = makeModel(units: DocumentUnits(length: .inches))
        #expect(inches.valueBoxContent(for: id(other.width))?.text == "2.3622")
    }

    @Test func aReferenceOrWiredDimensionOpensNoBox() {
        let (model, rectangle, _) = makeModel()
        model.choose(.select)
        model.setDriving(false, of: rectangle.height)
        #expect(model.valueBoxContent(for: id(rectangle.height)) == nil, "a reference")
        #expect(model.valueBoxContent(for: OverlayDimensionID("feature/1")) == nil, "not a sketch dimension")
        let wired = SketchEditorModel(sketch: rectangle.sketch, plane: .xy, wired: [rectangle.width])
        #expect(wired.valueBoxContent(for: id(rectangle.width)) == nil, "wired")
    }

    @Test func returnCommitsOneChangeDimension() async throws {
        let (model, rectangle, host) = makeModel()
        let outcome = await model.commitValue("70", to: id(rectangle.width))
        #expect(outcome == .accepted)
        #expect(host.commits.count == 1)
        #expect(host.commits.first?.name == "Change Dimension")
        #expect(try #require(model.sketch.dimensions[rectangle.width]).value == 70)
    }

    @Test func anUntouchedReturnIsNoStep() async {
        let (model, rectangle, host) = makeModel()
        let outcome = await model.commitValue("60", to: id(rectangle.width))
        #expect(outcome == .accepted)
        #expect(host.commits.isEmpty)
    }

    @Test func aValueThatCannotSolveIsRefused() async throws {
        // A diagonal fixed in length makes the width a conflict when it asks for more than the diagonal allows.
        var sketch = RectangleSketch().sketch
        let rectangle = RectangleSketch()
        sketch.addDimension(.distance(rectangle.corners[0], rectangle.corners[2]), value: Vector2(60, 40).length)
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        let host = RecordingHost(model)
        let before = model.sketch
        let outcome = await model.commitValue("70", to: id(rectangle.width))
        guard case .refused(let message) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(!message.isEmpty)
        #expect(host.commits.isEmpty)
        #expect(model.sketch == before)
    }

    @Test func nonNumbersAndBadValuesAreRefusedInTheBox() async {
        let (model, rectangle, host) = makeModel()
        let width = id(rectangle.width)
        #expect(await model.commitValue("abc", to: width) == .refused("“abc” isn't a number."))
        #expect(await model.commitValue("0", to: width) == .refused("A length must be more than 0 mm."))
        #expect(await model.commitValue("12,5", to: width) == .refused("“12,5” isn't a number."))
        var sketch = rectangle.sketch
        let angle = sketch.addDimension(.angle(rectangle.lines[0], rectangle.lines[1]), value: 90, isDriving: true)
        let angled = SketchEditorModel(sketch: sketch, plane: .xy)
        #expect(await angled.commitValue("200", to: id(angle)) == .refused("An angle must be between 0° and 180°."))
        #expect(host.commits.isEmpty)
    }

    @Test func aHostRefusalAfterTheCommitReachesTheBox() async {
        let (model, rectangle, host) = makeModel()
        model.events.checkValueCommit = { "Extrude: the profile is empty." }
        let outcome = await model.commitValue("70", to: id(rectangle.width))
        #expect(outcome == .refused("Extrude: the profile is empty."))
        #expect(host.commits.count == 1, "the step was committed; the host's check follows it")
    }
}

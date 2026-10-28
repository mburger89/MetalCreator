import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// A value typed for an existing dimension that would turn the sketch inside out is refused (spec §7), in the value box and in
/// the inspector alike.
@MainActor
struct FlipRefusalTests {
    func makeModel() -> (SketchEditorModel, RectangleSketch, RecordingHost) {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy) { _ in false }
        return (model, rectangle, RecordingHost(model))
    }

    @Test func aFlippingValueIsRefusedAndNothingCommits() async {
        let (model, rectangle, host) = makeModel()
        model.flipCheck = { _, _, _ in true }
        let id = SketchDimensionDrawing.overlayID(rectangle.width)
        let outcome = await model.commitValue("80", to: id)
        #expect(outcome == .refused("This value would flip the sketch."))
        #expect(host.commits.isEmpty)
        #expect(model.sketch.dimensions[rectangle.width]?.value == 60)
    }

    @Test func theInspectorRefusesTheSameWay() {
        let (model, rectangle, host) = makeModel()
        model.flipCheck = { _, _, _ in true }
        model.setValue("80", of: rectangle.width)
        #expect(model.refusal == "This value would flip the sketch.")
        #expect(host.commits.isEmpty)
        #expect(model.sketch.dimensions[rectangle.width]?.value == 60)
    }

    @Test func anOrdinaryValueStillCommits() async {
        let (model, rectangle, host) = makeModel()
        let id = SketchDimensionDrawing.overlayID(rectangle.width)
        let outcome = await model.commitValue("80", to: id)
        #expect(outcome == .accepted)
        #expect(host.commits.map(\.description) == ["Change d1"])
        #expect(host.commits.map(\.name) == ["Change Dimension"])
    }
}

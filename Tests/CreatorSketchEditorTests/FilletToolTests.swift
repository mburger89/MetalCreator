import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The Fillet tool (sketcher spec §3, §8): a click on a corner rounds it with the typed radius, as one step.
@MainActor
struct FilletToolTests {
    func makeModel() -> (SketchEditorModel, RecordingHost, RectangleSketch) {
        let rectangle = RectangleSketch(dimensioned: false)
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        model.choose(.fillet)
        return (model, RecordingHost(model), rectangle)
    }

    @Test func aClickOnACornerRoundsIt() throws {
        let (model, host, rectangle) = makeModel()
        model.click(at: Vector2(60.3, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Fillet Point 2 (5 mm)"])
        #expect(model.sketch.entities[rectangle.corners[1]] == nil, "the corner point is gone")
        let arcs = model.sketch.entityIDs.filter { if case .arc? = model.sketch.entities[$0]?.kind { true } else { false } }
        #expect(arcs.count == 1)
        let radius = try #require(model.sketch.dimensions.values.first { $0.kind == .radius(arcs[0]) })
        #expect(radius.value == 5)
        #expect(model.solution.status.isUsable)
    }

    @Test func theTypedRadiusIsUsed() {
        let (model, host, _) = makeModel()
        model.setFilletRadius("2.5 mm")
        #expect(model.options.filletRadius == 2.5 && model.refusal == nil)
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Fillet Point 1 (2.5 mm)"])
    }

    @Test(arguments: ["0", "-1", "abc", ""])
    func aRadiusThatIsntASizeIsRefused(_ text: String) {
        let (model, host, _) = makeModel()
        model.setFilletRadius(text)
        #expect(model.refusal == "A fillet radius must be a number more than 0 mm.")
        #expect(model.options.filletRadius == 5 && host.commits.isEmpty)
    }

    /// Review Focus 2: a radius the corner can't hold is refused in the command's words, with the largest that fits,
    /// and nothing is stored.
    @Test func aRadiusTooLargeForTheCornerIsRefused() {
        let (model, host, rectangle) = makeModel()
        model.setFilletRadius("50")
        model.click(at: Vector2(60.3, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "Radius 50 mm is too large for this corner (max ≈ 40 mm).")
        #expect(model.sketch.entities[rectangle.corners[1]] != nil)
    }

    @Test func aClickOnALineAwayFromItsCornersSaysWhatToClick() {
        let (model, host, _) = makeModel()
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "Click the corner where two lines meet.")
    }
}

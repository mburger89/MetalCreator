import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The sketch editor's chips are sized by the measure the view hands the model (gap S5-c, MetalUI C23): the model asks
/// it for the pointer readout and for the inferred constraints' names, and nothing estimates a width from the length.
@MainActor
struct ChipMeasureTests {
    let size = ViewportSize(width: 1200, height: 700)

    @Test func theInferenceChipIsSizedLikeTheReadoutChipForItsText() throws {
        let chip = try #require(InferenceChip(kinds: [.pointOn, .tangent], pointer: ScreenPoint(300, 300), in: size,
                                              measuring: .fake))
        #expect(chip.text == "Point on · Tangent")
        #expect(chip.size == ReadoutChip.size(of: chip.text, measuring: .fake))
    }

    @Test func theInferenceChipFollowsTheMeasureNotTheCharacterCount() throws {
        let measure = TextMeasure { _ in ViewportSize(width: 140.2, height: 12) }
        let chip = try #require(InferenceChip(kinds: [.horizontal], pointer: ScreenPoint(300, 300), in: size, measuring: measure))
        #expect(chip.size.width == 141 + 2 * ReadoutChip.padding)
    }

    @Test func theModelAsksTheMeasureForTheReadoutAndTheInferenceChips() throws {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xy)
        model.choose(.point)
        let projector = ViewportProjector(pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2,
                                                           projection: .orthographic), size: size)
        model.pointerMoved(to: ScreenPoint(600, 350), modifiers: [], projector: projector)
        let narrow = try #require(model.readoutChip(measuring: TextMeasure { _ in ViewportSize(width: 10, height: 12) }))
        let wide = try #require(model.readoutChip(measuring: TextMeasure { _ in ViewportSize(width: 110, height: 12) }))
        #expect(narrow.size.width == 10 + 2 * ReadoutChip.padding)
        #expect(wide.size.width == 110 + 2 * ReadoutChip.padding)
    }
}

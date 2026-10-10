import CreatorGeometry
import CreatorSketch
import CreatorViewport
import MetalUI
import Testing
@testable import CreatorSketchEditor

/// The glyphs of what a click would infer (sketcher spec §8: "a glyph previews each inferred constraint"), in a chip
/// below and right of the pointer.
@MainActor
struct InferenceGlyphTests {
    func makeModel(_ tool: SketchTool, _ sketch: Sketch = Sketch()) -> SketchEditorModel {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return model
    }

    func inferred(_ model: SketchEditorModel, at p: Vector2, modifiers: ViewportModifiers = []) -> [SketchConstraintKind] {
        model.hover(at: p, tolerance: 1, modifiers: modifiers)
        return model.preview.inferred
    }

    @Test func aLinesEndShowsWhatItWouldInfer() {
        var sketch = Sketch()
        sketch.addLine(Vector2(0, 40), Vector2(40, 40))
        let model = makeModel(.line, sketch)
        #expect(inferred(model, at: Vector2(20, 40.3)) == [.pointOn], "the first click would land on the line")
        #expect(inferred(model, at: Vector2(20, 40.3), modifiers: .command).isEmpty, "⌘ suppresses point on")
        #expect(inferred(model, at: Vector2(0.2, 39.8)) == [.coincident], "or share its end")
        #expect(inferred(model, at: Vector2(0.2, 39.8), modifiers: .command) == [.coincident], "⌘ never unshares a point")
        #expect(inferred(model, at: Vector2(10, 10)).isEmpty)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        #expect(inferred(model, at: Vector2(20, 0.4)) == [.horizontal])
        #expect(inferred(model, at: Vector2(0.3, 20)) == [.vertical])
        #expect(inferred(model, at: Vector2(0.3, 20), modifiers: .command).isEmpty, "⌘ suppresses it")
        #expect(inferred(model, at: Vector2(20, 39.7)) == [.pointOn])
    }

    @Test func aLineLeavingAnArcShowsTangent() {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let start = sketch.addPoint(Vector2(10, 0))
        let end = sketch.addPoint(Vector2(0, 10))
        sketch.addArc(center: center, start: start, end: end)
        let model = makeModel(.line, sketch)
        model.click(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        #expect(inferred(model, at: Vector2(-20, 10.4)) == [.tangent], "tangent wins over horizontal")
    }

    @Test func clicksThatPlaceNoPointInferNothing() {
        var sketch = Sketch()
        sketch.addPoint(Vector2(10, 0))
        let model = makeModel(.circle, sketch)
        model.click(at: .zero, tolerance: 1, modifiers: [])
        #expect(inferred(model, at: Vector2(10.2, 0)).isEmpty, "a circle's radius point isn't kept")
        model.choose(.select)
        #expect(inferred(model, at: Vector2(10.2, 0)).isEmpty)
    }

    @Test func theChipSitsBelowRightOfThePointer() throws {
        let size = ViewportSize(width: 400, height: 300)
        let chip = try #require(InferenceChip(kinds: [.horizontal], pointer: ScreenPoint(200, 150), in: size))
        #expect(chip.text == "Horizontal")
        #expect(chip.origin == ScreenPoint(200 + ReadoutChip.gap, 150 + ReadoutChip.gap))
        let two = try #require(InferenceChip(kinds: [.pointOn, .tangent], pointer: ScreenPoint(200, 150), in: size))
        #expect(two.text == "Point on · Tangent" && two.size.width > chip.size.width)
        #expect(InferenceChip(kinds: [], pointer: ScreenPoint(200, 150), in: size) == nil)
    }

    @Test func theChipMovesLeftAndUpAtTheModelAreasEdges() throws {
        let size = ViewportSize(width: 400, height: 300)
        let chip = try #require(InferenceChip(kinds: [.vertical], pointer: ScreenPoint(390, 290), in: size))
        #expect(abs(chip.origin.x + chip.size.width - (390 - ReadoutChip.gap)) < 1e-9, "left of the pointer")
        #expect(abs(chip.origin.y + chip.size.height - (290 - ReadoutChip.gap)) < 1e-9, "above it")
        let inset = try #require(InferenceChip(kinds: [.vertical], pointer: ScreenPoint(250, 150), in: size,
                                               modelArea: ViewportInsets(trailing: 100)))
        #expect(inset.origin.x + inset.size.width <= 300, "clear of a panel on the trailing side")
        #expect(InferenceChip(kinds: [.vertical], pointer: ScreenPoint(20, 10), in: ViewportSize(width: 60, height: 30)) == nil)
    }

    @Test func theModelPlacesTheChipAtThePointer() throws {
        let model = makeModel(.line)
        let size = ViewportSize(width: 400, height: 300)
        let projector = ViewportProjector(pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2,
                                                           projection: .orthographic), size: size)
        model.click(at: .zero, tolerance: 1, modifiers: [])
        model.pointerMoved(to: ScreenPoint(300, 151), projector: projector)
        let chip = try #require(model.inferenceChip, "a pointer just below the start's height infers horizontal")
        #expect(chip == InferenceChip(kinds: [.horizontal], pointer: ScreenPoint(300, 151), in: size))
        #expect(chip == InferenceChip(kinds: [.horizontal], pointer: ScreenPoint(300, 151), in: size,
                                      avoiding: model.readoutChip), "the readout above the pointer is already clear")
        model.pointerMoved(to: nil, projector: projector)
        #expect(model.inferenceChip == nil)
    }

    func overlap(_ a: (origin: ScreenPoint, size: ViewportSize), _ b: (origin: ScreenPoint, size: ViewportSize)) -> Bool {
        a.origin.x < b.origin.x + b.size.width && b.origin.x < a.origin.x + a.size.width
            && a.origin.y < b.origin.y + b.size.height && b.origin.y < a.origin.y + a.size.height
    }

    /// Near the model area's bottom the readout stays above the pointer, where the glyphs would go up to; near its top
    /// the readout flips below, where the glyphs would sit. Either way they stack beyond it, never over it.
    @Test(arguments: [ScreenPoint(200, 290), ScreenPoint(200, 10), ScreenPoint(390, 290), ScreenPoint(390, 10)])
    func theChipKeepsClearOfTheReadout(_ pointer: ScreenPoint) throws {
        let size = ViewportSize(width: 400, height: 300)
        let readout = try #require(ReadoutChip(text: "20.0 mm · 0.0°", pointer: pointer, in: size))
        let chip = try #require(InferenceChip(kinds: [.horizontal], pointer: pointer, in: size, avoiding: readout))
        #expect(!overlap((chip.origin, chip.size), (readout.origin, readout.size)))
        #expect(chip.origin.y >= ReadoutChip.margin && chip.origin.y + chip.size.height <= 300 - ReadoutChip.margin)
    }

    /// The model places both chips while a line is drawn near the view's bottom and top edges.
    @Test func theModelKeepsBothChipsApart() throws {
        let model = makeModel(.line)
        let size = ViewportSize(width: 400, height: 300)
        let projector = ViewportProjector(pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2,
                                                           projection: .orthographic), size: size)
        model.click(at: .zero, tolerance: 1, modifiers: [])
        for pointer in [ScreenPoint(200.4, 292), ScreenPoint(200.4, 8)] {
            model.pointerMoved(to: pointer, projector: projector)
            let readout = try #require(model.readoutChip, "a line's length and angle")
            let chip = try #require(model.inferenceChip, "straight above or below the start infers vertical")
            #expect(chip.text == "Vertical")
            #expect(!overlap((chip.origin, chip.size), (readout.origin, readout.size)))
        }
    }

    @Test func theChipViewHoldsItsText() throws {
        let text: [SketchConstraintKind] = [.coincident, .pointOn, .tangent]
        let chip = try #require(InferenceChip(kinds: text, pointer: ScreenPoint(300, 300), in: ViewportSize(width: 1200, height: 700)))
        let scene = renderHeadless {
            ZStack(alignment: .topLeading) { InferenceChipView(chip: chip) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        #expect(scene.glyphs.count >= chip.text.filter { !$0.isWhitespace }.count - 1)
        for glyph in scene.glyphs {
            let minX = Double(glyph.bounds.origin.x) / 2
            let maxX = Double(glyph.bounds.origin.x + glyph.bounds.size.width) / 2
            #expect(minX >= chip.origin.x && maxX <= chip.origin.x + chip.size.width, "a glyph spills out")
        }
    }
}

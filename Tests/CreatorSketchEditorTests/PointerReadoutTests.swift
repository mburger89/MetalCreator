import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Foundation
import Testing
@testable import CreatorSketchEditor

/// The live readout by the pointer while drawing (user, 2026-10-09): the values a click would commit (after
/// horizontal and vertical snapping), one decimal. A line's angle is counter-clockwise from the plane's +x axis,
/// 0 up to (not including) 360°; an arc's sweep runs counter-clockwise from its start, as `Sketch.addArc` draws it.
@MainActor
struct PointerReadoutTests {
    func makeModel(_ tool: SketchTool, _ sketch: Sketch = Sketch()) -> SketchEditorModel {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return model
    }

    func hover(_ model: SketchEditorModel, _ x: Double, _ y: Double, tolerance: Double = 1) -> String? {
        model.hover(at: Vector2(x, y), tolerance: tolerance, modifiers: [])
        return model.pointerReadout
    }

    @Test func aLineReadsItsLengthAndAngleAfterTheFirstClick() {
        let model = makeModel(.line)
        #expect(hover(model, 3, 4) == nil, "nothing before the first click")
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        #expect(hover(model, 24.5 * cos(.pi / 6), 24.5 * sin(.pi / 6)) == "24.5 mm · 30.0°")
    }

    @Test func aLineReadsTheSnappedEnd() {
        let model = makeModel(.line)
        model.click(at: Vector2(10, 10), tolerance: 1, modifiers: [])
        #expect(hover(model, 34.5, 10.8) == "24.5 mm · 0.0°", "snapped horizontal: as it would be committed")
        #expect(hover(model, 10.6, -20) == "30.0 mm · 270.0°", "snapped vertical")
    }

    @Test(arguments: [
        (Vector2(-10, -10), "14.1 mm · 225.0°"),
        (Vector2(-10, 0), "10.0 mm · 180.0°"),
        (Vector2(0, 10), "10.0 mm · 90.0°"),
        (Vector2(10, -0.06), "10.0 mm · 359.7°"),
        (Vector2(10, -0.0001), "10.0 mm · 0.0°"),
    ])
    func aLinesAngleRunsCounterClockwiseFromZeroToUnder360(_ end: Vector2, _ text: String) {
        let model = makeModel(.line)
        model.click(at: Vector2(0, 0), tolerance: 1e-6, modifiers: [])
        #expect(hover(model, end.x, end.y, tolerance: 1e-6) == text)
    }

    @Test func aCircleReadsItsDiameterAfterTheCentre() {
        let model = makeModel(.circle)
        #expect(hover(model, 6, 8) == nil)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        #expect(hover(model, 6, 8) == "⌀ 20.0 mm")
    }

    @Test func anArcReadsItsRadiusThenItsSweep() {
        let model = makeModel(.arc)
        #expect(hover(model, 12, 0) == nil)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        #expect(hover(model, 12, 0) == "R 12.0 mm")
        model.click(at: Vector2(12, 0), tolerance: 1, modifiers: [])
        #expect(hover(model, 0, 5) == "R 12.0 mm · 90.0°", "the end lands on the start's radius")
        #expect(hover(model, 0, -5) == "R 12.0 mm · 270.0°", "counter-clockwise from the start")
    }

    @Test func thePointToolReadsThePointersPosition() {
        var sketch = Sketch()
        sketch.addPoint(Vector2(5, 5))
        let model = makeModel(.point, sketch)
        #expect(hover(model, 12, 8.5) == "12.0, 8.5")
        #expect(hover(model, -3.24, -0.01) == "-3.2, 0.0", "never −0.0")
        #expect(hover(model, 5.3, 5.2) == "5.0, 5.0", "snapped onto the existing point")
    }

    @Test func theReadoutEndsWithTheStroke() {
        let model = makeModel(.line)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        #expect(hover(model, 10, 10) != nil)
        model.escape()
        #expect(model.pointerReadout == nil, "Esc")
        model.choose(.circle)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        #expect(hover(model, 10, 10) != nil)
        model.click(at: Vector2(10, 10), tolerance: 1, modifiers: [])
        #expect(model.pointerReadout == nil, "the circle is drawn")
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        #expect(hover(model, 10, 10) != nil)
        model.hover(at: nil, tolerance: 1, modifiers: [])
        #expect(model.pointerReadout == nil, "the pointer left the view")
        model.choose(.select)
        #expect(hover(model, 10, 10) == nil, "Select draws nothing")
    }

    @Test func theChipFollowsThePointerOnScreen() throws {
        let model = makeModel(.point)
        let size = ViewportSize(width: 400, height: 300)
        let projector = ViewportProjector(pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2,
                                                           projection: .orthographic), size: size)
        #expect(model.readoutChip == nil)
        model.pointerMoved(to: ScreenPoint(200, 150), projector: projector)
        let chip = try #require(model.readoutChip)
        #expect(chip.text == "0.0, 0.0")
        #expect(chip == ReadoutChip(text: "0.0, 0.0", pointer: ScreenPoint(200, 150), in: size))
        model.pointerMoved(to: nil, projector: projector)
        #expect(model.readoutChip == nil, "the pointer left the view")
    }

    @Test func theChipSitsCentredAboveThePointer() {
        let size = ViewportSize(width: 400, height: 300)
        let chip = ReadoutChip(text: "24.5 mm · 30.0°", pointer: ScreenPoint(200, 150), in: size)
        #expect(abs(chip.origin.x + chip.size.width / 2 - 200) < 1e-9, "centred on the pointer")
        #expect(abs(chip.origin.y + chip.size.height - (150 - ReadoutChip.gap)) < 1e-9, "a gap above it")
        #expect(chip.size.width > 0 && chip.size.height > 0)
    }

    @Test func theChipFlipsBelowThePointerAtTheTop() {
        let size = ViewportSize(width: 400, height: 300)
        let chip = ReadoutChip(text: "⌀ 20.0 mm", pointer: ScreenPoint(200, 20), in: size)
        #expect(abs(chip.origin.y - (20 + ReadoutChip.gap)) < 1e-9)
    }

    @Test func theChipStaysInsideTheViewAtTheSides() {
        let size = ViewportSize(width: 400, height: 300)
        let left = ReadoutChip(text: "24.5 mm · 30.0°", pointer: ScreenPoint(3, 150), in: size)
        #expect(abs(left.origin.x - ReadoutChip.margin) < 1e-9)
        let right = ReadoutChip(text: "24.5 mm · 30.0°", pointer: ScreenPoint(398, 150), in: size)
        #expect(abs(right.origin.x + right.size.width - (400 - ReadoutChip.margin)) < 1e-9)
    }

    @Test func aLongerTextMakesAWiderChip() {
        let size = ViewportSize(width: 400, height: 300)
        let short = ReadoutChip(text: "R 1.0 mm", pointer: ScreenPoint(200, 150), in: size)
        let long = ReadoutChip(text: "R 1.0 mm · 90.0°", pointer: ScreenPoint(200, 150), in: size)
        #expect(long.size.width > short.size.width)
    }
}

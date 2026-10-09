import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Foundation
import Observation
import Testing
@testable import CreatorSketchEditor

/// The readout while a sketch point is dragged (user, 2026-10-09): the solved values, what the release keeps, in
/// the drawing readout's format. A lone line end reads its line's length and angle, an arc's start or end its arc's
/// radius and sweep, and anything else (a centre, a free point, a corner shared by several curves or joined to another
/// point by a coincident constraint) its position. It updates every drag step and goes with the release.
@MainActor
struct DragReadoutTests {
    func makeModel(_ sketch: Sketch, tool: SketchTool = .select) -> SketchEditorModel {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return model
    }

    /// Presses on `from`, drags to `to`, and returns the readout before the release.
    func drag(_ model: SketchEditorModel, from: Vector2, to: Vector2) -> String? {
        #expect(model.beginDrag(at: from, tolerance: 1), "the press is on a point")
        model.drag(to: to)
        return model.pointerReadout
    }

    @Test func aLoneLineEndReadsItsLinesLengthAndAngle() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        if case .line(let start, _)? = sketch.entities[line]?.kind { sketch.add(.fix(start, at: .zero)) }
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(10, 0), to: Vector2(0, 24.5)) == "24.5 mm · 90.0°")
    }

    @Test func aLinesStartReadsTheLineFromItsStart() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        if case .line(_, let end)? = sketch.entities[line]?.kind { sketch.add(.fix(end, at: Vector2(10, 0))) }
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(0, 0), to: Vector2(10, -20)) == "20.0 mm · 90.0°",
                "the line's own direction, start to end")
    }

    /// The values are the solve's: a line whose length is dimensioned keeps it however far the pointer goes.
    @Test func aConstrainedLineReadsItsSolvedLength() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(20, 0))
        if case .line(let start, _)? = sketch.entities[line]?.kind { sketch.add(.fix(start, at: .zero)) }
        sketch.addDimension(.length(line), value: 20)
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(20, 0), to: Vector2(0, 35)) == "20.0 mm · 90.0°")
    }

    @Test func anArcsEndReadsItsRadiusAndSweep() {
        var sketch = Sketch()
        let center = sketch.addPoint(Vector2(0, 0))
        let start = sketch.addPoint(Vector2(12, 0))
        let end = sketch.addPoint(Vector2(0, 12))
        sketch.addArc(center: center, start: start, end: end)
        sketch.add(.fix(center, at: .zero))
        sketch.add(.fix(start, at: Vector2(12, 0)))
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(0, 12), to: Vector2(-30, 0)) == "R 12.0 mm · 180.0°",
                "the end lands on the radius the solve keeps")
    }

    /// The sweep runs counter-clockwise from the start: an end dragged to 135° reads 135°, never the 225° the other
    /// way round.
    @Test func anArcsSweepRunsCounterClockwiseFromItsStart() {
        var sketch = Sketch()
        let center = sketch.addPoint(Vector2(0, 0))
        let start = sketch.addPoint(Vector2(12, 0))
        let end = sketch.addPoint(Vector2(0, 12))
        sketch.addArc(center: center, start: start, end: end)
        sketch.add(.fix(center, at: .zero))
        sketch.add(.fix(start, at: Vector2(12, 0)))
        let model = makeModel(sketch)
        let text = drag(model, from: Vector2(0, 12), to: Vector2(-12, 12))
        let solved = model.sketch.position(of: end) ?? .zero
        let angle = atan2(solved.y, solved.x) * 180 / .pi
        #expect(abs(angle - 135) < 1, "the solve puts the end near the pointer's 135°")
        #expect(text == "R 12.0 mm · \(ReadoutText.number(angle))°", "counter-clockwise from the start at 0°, not 360° less")
    }

    @Test func anArcsStartReadsItsRadiusAndSweep() {
        var sketch = Sketch()
        let center = sketch.addPoint(Vector2(0, 0))
        let start = sketch.addPoint(Vector2(12, 0))
        let end = sketch.addPoint(Vector2(0, 12))
        sketch.addArc(center: center, start: start, end: end)
        sketch.add(.fix(center, at: .zero))
        sketch.add(.fix(end, at: Vector2(0, 12)))
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(12, 0), to: Vector2(0, -30)) == "R 12.0 mm · 180.0°")
    }

    @Test func aCirclesCentreReadsItsPosition() {
        var sketch = Sketch()
        sketch.addCircle(center: Vector2(5, 5), radius: 3)
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(5, 5), to: Vector2(12, 8.5)) == "12.0, 8.5")
    }

    @Test func anArcsCentreReadsItsPosition() {
        var sketch = Sketch()
        let center = sketch.addPoint(Vector2(0, 0))
        let start = sketch.addPoint(Vector2(12, 0))
        let end = sketch.addPoint(Vector2(0, 12))
        sketch.addArc(center: center, start: start, end: end)
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(0, 0), to: Vector2(-3, 4)) == "-3.0, 4.0")
    }

    @Test func aFreePointReadsItsPosition() {
        var sketch = Sketch()
        sketch.addPoint(Vector2(5, 5))
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(5, 5), to: Vector2(12, 8.5)) == "12.0, 8.5")
    }

    /// A corner shared by two lines reads its position, the solved one: the rectangle's vertical side keeps the
    /// corner's x on the pointer's, its fixed corner and horizontal sides hold the rest.
    @Test func aCornerReadsItsPosition() {
        let rectangle = RectangleSketch(dimensioned: false)
        let model = makeModel(rectangle.sketch)
        #expect(drag(model, from: Vector2(60.3, 40.2), to: Vector2(70, 50)) == "70.0, 50.0")
    }

    /// Precedence: a point that is an arc's end and a line's end is shared, so it reads its position, not either
    /// curve's values.
    @Test func aPointThatEndsAnArcAndALineReadsItsPosition() {
        var sketch = Sketch()
        let center = sketch.addPoint(Vector2(0, 0))
        let start = sketch.addPoint(Vector2(12, 0))
        let end = sketch.addPoint(Vector2(0, 12))
        sketch.addArc(center: center, start: start, end: end)
        let far = sketch.addPoint(Vector2(-20, 12))
        sketch.addLine(from: end, to: far)
        let model = makeModel(sketch)
        let text = drag(model, from: Vector2(0, 12), to: Vector2(1, 13))
        let solved = model.sketch.position(of: end) ?? Vector2(.nan, .nan)
        #expect(text == ReadoutText.position(solved), "the solved position")
        #expect(text?.contains("mm") == false)
    }

    /// Construction geometry counts: a construction line sharing a line's end makes it a corner.
    @Test func aLineEndSharedWithConstructionGeometryReadsItsPosition() {
        var sketch = Sketch()
        let start = sketch.addPoint(Vector2(0, 0))
        let end = sketch.addPoint(Vector2(10, 0))
        sketch.addLine(from: start, to: end)
        sketch.add(.fix(start, at: .zero))
        let other = sketch.addPoint(Vector2(10, 10))
        sketch.addLine(from: end, to: other, isConstruction: true)
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(10, 0), to: Vector2(12, 3)) == ReadoutText.position(model.sketch.position(of: end) ?? .zero))
        #expect(model.pointerReadout?.contains("mm") == false)
    }

    /// Other constraints on a lone line end (on a curve, a midpoint) hold it but don't make it a corner: it still
    /// reads its line, as solved.
    @Test func aLineEndOnACurveStillReadsItsLine() {
        var sketch = Sketch()
        let start = sketch.addPoint(Vector2(0, 0))
        let end = sketch.addPoint(Vector2(10, 0))
        sketch.addLine(from: start, to: end)
        sketch.add(.fix(start, at: .zero))
        let low = sketch.addPoint(Vector2(10, -50))
        let high = sketch.addPoint(Vector2(10, 50))
        let rail = sketch.addLine(from: low, to: high, isConstruction: true)
        sketch.add(.fix(low, at: Vector2(10, -50)))
        sketch.add(.fix(high, at: Vector2(10, 50)))
        sketch.add(.pointOn(point: end, curve: rail))
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(10, 0), to: Vector2(10, 10)) == "14.1 mm · 45.0°")
    }

    @Test func aLineEndAtAMidpointStillReadsItsLine() {
        var sketch = Sketch()
        let start = sketch.addPoint(Vector2(0, 0))
        let end = sketch.addPoint(Vector2(10, 0))
        sketch.addLine(from: start, to: end)
        sketch.add(.fix(start, at: .zero))
        let low = sketch.addPoint(Vector2(10, -5))
        let high = sketch.addPoint(Vector2(10, 5))
        let other = sketch.addLine(from: low, to: high)
        sketch.add(.fix(low, at: Vector2(10, -5)))
        sketch.add(.fix(high, at: Vector2(10, 5)))
        sketch.add(.midpoint(point: end, line: other))
        let model = makeModel(sketch)
        #expect(drag(model, from: Vector2(10, 0), to: Vector2(14, 6)) == "10.0 mm · 0.0°", "held at the midpoint")
    }

    /// Two line ends joined by a coincident constraint are a corner too.
    @Test func aLineEndJoinedByACoincidentConstraintReadsItsPosition() {
        var sketch = Sketch()
        let first = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let second = sketch.addLine(Vector2(10, 0), Vector2(10, 10))
        if case .line(_, let a)? = sketch.entities[first]?.kind, case .line(let b, _)? = sketch.entities[second]?.kind {
            sketch.add(.coincident(a, b))
        }
        let model = makeModel(sketch)
        let text = drag(model, from: Vector2(10, 0), to: Vector2(12, 3))
        #expect(text?.contains("mm") == false && text?.contains(",") == true)
    }

    /// The drag's readout wins over the tool's: the Point tool would read the pointer, the drag reads the line.
    @Test func theDragsReadoutWinsOverTheTools() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        if case .line(let start, _)? = sketch.entities[line]?.kind { sketch.add(.fix(start, at: .zero)) }
        let model = makeModel(sketch, tool: .point)
        #expect(drag(model, from: Vector2(10, 0), to: Vector2(0, 24.5)) == "24.5 mm · 90.0°")
    }

    @Test func theReadoutUpdatesEveryStepAndGoesWithTheRelease() {
        let rectangle = RectangleSketch(dimensioned: false)
        let model = makeModel(rectangle.sketch)
        #expect(model.pointerReadout == nil, "nothing before the press")
        #expect(model.beginDrag(at: Vector2(60.3, 40.2), tolerance: 1))
        #expect(model.pointerReadout == "60.0, 40.0", "the press shows where the point is")
        model.drag(to: Vector2(70, 50))
        #expect(model.pointerReadout == "70.0, 50.0")
        model.drag(to: Vector2(65, 45))
        #expect(model.pointerReadout == "65.0, 45.0")
        model.endDrag(at: Vector2(80, 50))
        #expect(model.pointerReadout == nil, "gone with the release")
    }

    /// Undo in the middle of a drag (`reload`) ends it, and its readout.
    @Test func theReadoutGoesWhenTheDragIsCancelled() {
        let model = makeModel(RectangleSketch(dimensioned: false).sketch)
        #expect(model.beginDrag(at: Vector2(60.3, 40.2), tolerance: 1))
        model.drag(to: Vector2(70, 50))
        #expect(model.pointerReadout != nil)
        model.reload(RectangleSketch().sketch, plane: .xy)
        #expect(model.pointerReadout == nil)
    }

    /// Finishing the sketch mid-drag ends the drag: no stale chip in an editor that is used again, and the later
    /// release commits nothing.
    @Test func finishingEndsADrag() {
        let model = makeModel(RectangleSketch(dimensioned: false).sketch)
        let host = RecordingHost(model)
        #expect(model.beginDrag(at: Vector2(60.3, 40.2), tolerance: 1))
        model.drag(to: Vector2(70, 50))
        model.finish()
        #expect(host.finishes == 1)
        #expect(model.pointerReadout == nil)
        model.drag(to: Vector2(75, 55))
        model.endDrag(at: Vector2(80, 50))
        #expect(host.commits.isEmpty, "the release after finishing records no step")
        let corner = model.sketch.position(of: RectangleSketch().corners[2]) ?? .zero
        #expect((corner - Vector2(60, 40)).length < 1e-6, "the uncommitted drag is dropped, as a stroke is")
    }

    /// A release that moved nothing (the fixed corner) still hides the chip: its views hear the drag end.
    @Test func theChipsObserversHearTheRelease() {
        let model = makeModel(RectangleSketch().sketch)
        #expect(model.beginDrag(at: Vector2(0.2, 0.1), tolerance: 1))
        model.drag(to: Vector2(10, 10))
        let heard = Heard()
        withObservationTracking { _ = model.pointerReadout } onChange: { MainActor.assumeIsolated { heard.value = true } }
        model.endDrag(at: Vector2(10, 10))
        #expect(heard.value)
        #expect(model.pointerReadout == nil)
    }

    /// Through the viewport: the chip appears on the press, follows the pointer on every drag step (the viewport
    /// sends no hover during a drag), and goes on the release.
    @Test func theChipFollowsTheDragOnScreen() throws {
        let rectangle = RectangleSketch(dimensioned: false)
        let model = makeModel(rectangle.sketch)
        let size = ViewportSize(width: 400, height: 300)
        let projector = ViewportProjector(pose: CameraPose(target: Vector3(30, 20, 0), distance: 100, pitch: .pi / 2,
                                                           projection: .orthographic), size: size)
        let press = try #require(projector.screenPoint(of: Vector3(60, 40, 0)))
        #expect(model.dragBegan(at: press, modifiers: [], projector: projector))
        #expect(model.readoutChip == ReadoutChip(text: "60.0, 40.0", pointer: press, in: size))
        let step = try #require(projector.screenPoint(of: Vector3(70, 50, 0)))
        model.dragMoved(to: step, modifiers: [], projector: projector)
        #expect(model.readoutChip == ReadoutChip(text: "70.0, 50.0", pointer: step, in: size))
        let next = try #require(projector.screenPoint(of: Vector3(65, 30, 0)))
        model.dragMoved(to: next, modifiers: [], projector: projector)
        let chip = try #require(model.readoutChip)
        #expect(chip.text == "65.0, 30.0")
        #expect(chip == ReadoutChip(text: chip.text, pointer: next, in: size), "it follows the pointer")
        model.dragEnded(at: next, modifiers: [], projector: projector)
        #expect(model.readoutChip == nil)
    }
}

/// Whether an observation fired.
@MainActor
final class Heard {
    var value = false
}

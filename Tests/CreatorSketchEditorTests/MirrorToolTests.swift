import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The Mirror tool (sketcher spec §3, §8): select, then click the line to mirror about; one step.
@MainActor
struct MirrorToolTests {
    /// A vertical axis along x = 0 and a slanted line to its right.
    func fixture() -> (sketch: Sketch, axis: SketchEntityID, line: SketchEntityID) {
        var sketch = Sketch()
        let axis = sketch.addLine(Vector2(0, -10), Vector2(0, 30), isConstruction: true)
        let line = sketch.addLine(Vector2(5, 0), Vector2(15, 10))
        return (sketch, axis, line)
    }

    func makeModel(_ sketch: Sketch) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.mirror)
        return (model, RecordingHost(model))
    }

    func positions(_ sketch: Sketch) -> Set<[Double]> {
        Set(sketch.entityIDs.compactMap { id in sketch.position(of: id).map { [($0.x * 1e6).rounded(), ($0.y * 1e6).rounded()] } })
    }

    @Test func aClickOnALineMirrorsTheSelectionAboutIt() {
        let fixture = fixture()
        let (model, host) = makeModel(fixture.sketch)
        model.selection = [fixture.line]
        model.hover(at: Vector2(0.2, 29.8), tolerance: 1, modifiers: [])
        #expect(model.hovered == fixture.axis, "the axis, not its end point")
        model.click(at: Vector2(0.2, 15), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Mirror 1 entity"])
        let mirrored = positions(model.sketch)
        #expect(mirrored.contains([-5e6, 0]) && mirrored.contains([-15e6, 10e6]))
        let symmetric = model.sketch.constraints.values.filter { if case .symmetric = $0 { true } else { false } }
        #expect(symmetric.count == 2)
        #expect(model.selection == [fixture.line], "the selection stays, to mirror again")
    }

    @Test func theAxisInTheSelectionIsLeftOut() {
        let fixture = fixture()
        let (model, host) = makeModel(fixture.sketch)
        model.selection = [fixture.line, fixture.axis]
        model.click(at: Vector2(0.2, 15), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Mirror 1 entity"])
    }

    @Test func withNothingSelectedItSaysWhatToSelect() {
        let (model, host) = makeModel(fixture().sketch)
        model.click(at: Vector2(0.2, 15), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "Select the geometry to mirror first.")
    }

    @Test func aCircleIsNoAxis() {
        var sketch = fixture().sketch
        let circle = sketch.addCircle(center: Vector2(40, 0), radius: 5)
        let (model, host) = makeModel(sketch)
        model.selection = [circle]
        model.click(at: Vector2(45.2, 0), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "Mirror needs a line to mirror about.")
    }
}

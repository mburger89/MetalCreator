import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Trim and Extend (sketcher spec §3, §8): a click on a curve runs its command as one step; a refused command says
/// why and changes nothing.
@MainActor
struct ModifyToolTests {
    /// A horizontal line from (0, 0) to (40, 0) crossed by a vertical one from (20, −10) to (20, 10).
    func crossingLines() -> (sketch: Sketch, horizontal: SketchEntityID, vertical: SketchEntityID) {
        var sketch = Sketch()
        let horizontal = sketch.addLine(Vector2(0, 0), Vector2(40, 0))
        let vertical = sketch.addLine(Vector2(20, -10), Vector2(20, 10))
        return (sketch, horizontal, vertical)
    }

    func makeModel(_ sketch: Sketch, tool: SketchTool) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return (model, RecordingHost(model))
    }

    func ends(of line: SketchEntityID, in sketch: Sketch) -> [Vector2] {
        guard case .line(let start, let end)? = sketch.entities[line]?.kind else { return [] }
        return [start, end].compactMap { sketch.position(of: $0) }
    }

    @Test func trimRemovesTheSpanUnderTheClick() throws {
        let fixture = crossingLines()
        let (model, host) = makeModel(fixture.sketch, tool: .trim)
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Trim Line 1"])
        let ends = ends(of: fixture.horizontal, in: model.sketch)
        #expect(ends.count == 2 && (ends[1] - Vector2(20, 0)).length < 1e-9, "the line now ends where the other crosses it")
    }

    @Test func extendReachesTheNextCurve() {
        var sketch = Sketch()
        let short = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        sketch.addLine(Vector2(20, -10), Vector2(20, 10))
        let (model, host) = makeModel(sketch, tool: .extend)
        model.click(at: Vector2(9, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Extend Line 1"])
        let ends = ends(of: short, in: model.sketch)
        #expect(ends.count == 2 && (ends[1] - Vector2(20, 0)).length < 1e-9)
    }

    /// Review Focus 1: a trim that would take an exposed dimension with it (a trimmed line's length) is refused in the
    /// command's words, and nothing is stored.
    @Test func aTrimThatWouldRemoveAnExposedDimensionIsRefused() {
        var fixture = crossingLines()
        let length = fixture.sketch.addDimension(.length(fixture.horizontal), value: 40)
        fixture.sketch.dimensions[length]?.isExposed = true
        let (model, host) = makeModel(fixture.sketch, tool: .trim)
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "That would remove d1, which is exposed as an input. Stop exposing it first.")
        #expect(model.sketch.dimensions[length] != nil)
    }

    @Test func aRefusedExtendSaysWhy() {
        var sketch = Sketch()
        sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let (model, host) = makeModel(sketch, tool: .extend)
        model.click(at: Vector2(9, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "There is nothing to extend Line 1 to.")
    }

    @Test func theCommandToolsPointAtCurvesAndMarkNoPoint() {
        let fixture = crossingLines()
        let (model, host) = makeModel(fixture.sketch, tool: .trim)
        model.hover(at: Vector2(0.2, 0.1), tolerance: 1, modifiers: [])
        #expect(model.hovered == fixture.horizontal, "the line, not its end point")
        #expect(model.preview == .none, "nothing would be placed")
        model.click(at: Vector2(30, 30), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty && model.refusal == nil, "a click on nothing does nothing")
    }

    @Test func trimHasItsKey() {
        #expect(SketchTool.trim.key == "t" && SketchTool.extend.key == nil)
    }
}

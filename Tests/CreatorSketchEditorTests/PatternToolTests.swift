import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The Pattern tool (sketcher spec §3, §8): select, then click a point (circular) or a line (linear); one step.
@MainActor
struct PatternToolTests {
    func makeModel(_ sketch: Sketch) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.pattern)
        return (model, RecordingHost(model))
    }

    /// The centres of every circle, rounded to a micrometre.
    func circleCentres(_ sketch: Sketch) -> Set<[Double]> {
        Set(sketch.entityIDs.compactMap { id -> [Double]? in
            guard case .circle(let center, _)? = sketch.entities[id]?.kind, let at = sketch.position(of: center) else { return nil }
            return [(at.x * 1000).rounded() / 1000, (at.y * 1000).rounded() / 1000]
        })
    }

    @Test func aClickOnALinePatternsAlongIt() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: Vector2(0, 0), radius: 2)
        sketch.addLine(Vector2(0, -10), Vector2(10, -10), isConstruction: true)
        let (model, host) = makeModel(sketch)
        model.selection = [circle]
        model.click(at: Vector2(5, -9.8), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Linear pattern of 1 entity (×3)"])
        #expect(circleCentres(model.sketch) == [[0, 0], [20, 0], [40, 0]])
        #expect(model.selection == [circle])
    }

    @Test func aClickOnAPointPatternsAroundIt() {
        var sketch = Sketch()
        sketch.addPoint(Vector2(0, 0))
        let circle = sketch.addCircle(center: Vector2(10, 0), radius: 2)
        let (model, host) = makeModel(sketch)
        model.setPatternCount("4")
        model.selection = [circle]
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Circular pattern of 1 entity (×4)"])
        #expect(circleCentres(model.sketch) == [[10, 0], [0, 10], [-10, 0], [0, -10]])
    }

    @Test func theTypedSpacingIsUsed() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: Vector2(0, 0), radius: 2)
        sketch.addLine(Vector2(0, -10), Vector2(0, -20))
        let (model, _) = makeModel(sketch)
        model.setPatternSpacing("15 mm")
        model.setPatternCount("2")
        model.selection = [circle]
        model.click(at: Vector2(0.2, -15), tolerance: 1, modifiers: [])
        #expect(circleCentres(model.sketch) == [[0, 0], [0, -15]], "along the line, from its start toward its end")
    }

    @Test(arguments: ["1", "2.5", "abc", ""])
    func aCountThatIsntTwoOrMoreIsRefused(_ text: String) {
        let (model, _) = makeModel(Sketch())
        model.setPatternCount(text)
        #expect(model.refusal == "A pattern needs a whole number of instances, 2 or more.")
        #expect(model.options.patternCount == 3)
    }

    @Test func aSpacingThatIsntASizeIsRefused() {
        let (model, _) = makeModel(Sketch())
        model.setPatternSpacing("0")
        #expect(model.refusal == "A pattern spacing must be a number more than 0 mm.")
        #expect(model.options.patternSpacing == 20)
    }

    @Test func aCountOverTheLimitIsRefusedWhenItRuns() {
        var sketch = Sketch()
        sketch.addPoint(Vector2(0, 0))
        let circle = sketch.addCircle(center: Vector2(10, 0), radius: 2)
        let (model, host) = makeModel(sketch)
        model.setPatternCount("101")
        model.selection = [circle]
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "A pattern can have at most 100 instances.")
    }

    @Test func anArcOrNothingSelectedSaysWhatsMissing() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: Vector2(10, 0), radius: 2)
        sketch.addPoint(Vector2(0, 0))
        let (model, host) = makeModel(sketch)
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(model.refusal == "Select the geometry to pattern first.")
        model.selection = [circle]
        model.click(at: Vector2(12.1, 0), tolerance: 1, modifiers: [])
        #expect(model.refusal == "Click a point to pattern around, or a line to pattern along.")
        #expect(host.commits.isEmpty)
    }
}

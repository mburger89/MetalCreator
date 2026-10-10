import CreatorGeometry
import CreatorKernel
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Every commit the sketch editor makes carries a fixed step name (named undo steps): the kind of edit, never text
/// the person typed (a dimension's name) and never a number, which `SketchCommit.description` still has.
@MainActor
struct SketchStepNameTests {
    func makeModel(_ sketch: Sketch = Sketch(), tool: SketchTool = .select) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return (model, RecordingHost(model))
    }

    @Test func drawingNamesEachKindOfGeometry() {
        let (model, host) = makeModel(tool: .point)
        model.click(at: Vector2(1, 1), tolerance: 1, modifiers: [])
        model.choose(.line)
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(30, 0), tolerance: 1, modifiers: [])
        model.choose(.circle)
        model.click(at: Vector2(10, 40), tolerance: 1, modifiers: [])
        model.click(at: Vector2(13, 44), tolerance: 1, modifiers: [])
        model.choose(.arc)
        model.click(at: Vector2(50, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(60, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(50, 3), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.name) == ["Add Point", "Add Line", "Add Circle", "Add Arc"])
    }

    @Test func constraintsAndConstructionAreNamedByKind() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch)
        model.selection = [rectangle.lines[0], rectangle.lines[1]]
        model.addConstraint(.equal)
        model.selection = [rectangle.lines[0]]
        model.toggleConstruction()
        model.toggleConstruction()
        #expect(host.commits.map(\.name) == ["Add Constraint", "Make Construction", "Make Normal Geometry"])
        #expect(host.commits.first?.description == "Equal", "the finer description is kept for tests and logs")
    }

    @Test func dimensionStepsHaveFixedNamesWhateverTheDimensionIsCalled() {
        let rectangle = RectangleSketch()
        let (model, host) = makeModel(rectangle.sketch)
        model.setValue("80", of: rectangle.width)
        model.rename(rectangle.width, to: "Plate width")
        model.setExposed(true, of: rectangle.width)
        model.setExposed(false, of: rectangle.width)
        model.setDriving(false, of: rectangle.height)
        model.setDriving(true, of: rectangle.height)
        model.remove(.dimension(rectangle.height))
        #expect(host.commits.map(\.name) == [
            "Change Dimension", "Rename Dimension", "Expose Dimension", "Stop Exposing Dimension",
            "Make Dimension Reference", "Make Dimension Driving", "Delete",
        ])
        #expect(host.commits.map(\.description).contains("Rename d1 to Plate width"), "the typed name is in the description only")
        #expect(host.commits.allSatisfy { !$0.name.contains("Plate") && !$0.name.contains("d1") })
    }

    @Test func aDimensionToolPickIsAddDimension() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch, tool: .dimension)
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        model.click(at: Vector2(30, 20), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.name) == ["Add Dimension"])
    }

    @Test func deletingAndDraggingAPointAreNamed() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch)
        #expect(model.beginDrag(at: Vector2(60.3, 40.2), tolerance: 1))
        model.endDrag(at: Vector2(70, 50))
        model.selection = [rectangle.lines[2]]
        model.deleteSelection()
        #expect(host.commits.map(\.name) == ["Move Point", "Delete"])
    }

    @Test func filletsHaveNoRadiusInTheirName() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch, tool: .fillet)
        model.setFilletRadius("2.5")
        model.click(at: Vector2(60.3, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.name) == ["Fillet"])
        #expect(host.commits.first?.description.contains("2.5") == true, "the radius is in the description")
    }

    @Test func trimExtendMirrorAndPatternsAreNamed() {
        var crossing = Sketch()
        crossing.addLine(Vector2(0, 0), Vector2(40, 0))
        crossing.addLine(Vector2(20, -10), Vector2(20, 10))
        let (trim, trimmed) = makeModel(crossing, tool: .trim)
        trim.click(at: Vector2(35, 0), tolerance: 1, modifiers: [])
        #expect(trimmed.commits.map(\.name) == ["Trim"])

        var short = Sketch()
        short.addLine(Vector2(0, 0), Vector2(20, 0))
        short.addLine(Vector2(30, -10), Vector2(30, 10))
        let (extend, extended) = makeModel(short, tool: .extend)
        extend.click(at: Vector2(19, 0), tolerance: 1, modifiers: [])
        #expect(extended.commits.map(\.name) == ["Extend"])

        var mirrorSketch = Sketch()
        mirrorSketch.addLine(Vector2(0, -10), Vector2(0, 30), isConstruction: true)
        let line = mirrorSketch.addLine(Vector2(5, 0), Vector2(15, 10))
        let (mirror, mirrored) = makeModel(mirrorSketch, tool: .mirror)
        mirror.selection = [line]
        mirror.click(at: Vector2(0.2, 15), tolerance: 1, modifiers: [])
        #expect(mirrored.commits.map(\.name) == ["Mirror"])

        var linear = Sketch()
        let circle = linear.addCircle(center: Vector2(0, 0), radius: 2)
        linear.addLine(Vector2(0, -10), Vector2(10, -10), isConstruction: true)
        let (along, alongHost) = makeModel(linear, tool: .pattern)
        along.selection = [circle]
        along.click(at: Vector2(5, -9.8), tolerance: 1, modifiers: [])
        #expect(alongHost.commits.map(\.name) == ["Linear Pattern"])

        var round = Sketch()
        round.addPoint(Vector2(0, 0))
        let ring = round.addCircle(center: Vector2(10, 0), radius: 2)
        let (around, aroundHost) = makeModel(round, tool: .pattern)
        around.setPatternCount("4")
        around.selection = [ring]
        around.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(aroundHost.commits.map(\.name) == ["Circular Pattern"])
        #expect(aroundHost.commits.first?.description.contains("4") == true, "the count is in the description")
    }

    @Test func projectIsNamedProject() {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xz)
        let host = RecordingHost(model)
        model.choose(.project)
        let pick = EdgePick(key: EdgeKey([], []), matchCount: 1)
        let candidate = ProjectionCandidate(curve: .line(Vector2(0, 0), Vector2(30, 0)), pick: pick, solid: 0)
        model.events.projection = { _, _ in ProjectionResolution(candidates: [candidate], skipped: []) }
        model.project(.edge(solid: 0, EdgeID(1)))
        #expect(host.commits.map(\.name) == ["Project"])
    }

    @Test func aCommitMadeWithoutANameIsCalledEditSketch() {
        #expect(SketchCommit(sketch: Sketch(), description: "Vertical").name == "Edit Sketch")
    }
}

import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Dimensions (sketcher spec §8): the Dimension tool infers the kind from its picks and measures what's there; the
/// inspector edits value, name, "Expose as input" and driving, and removes constraints and dimensions.
@MainActor
struct DimensionTests {
    func makeModel(_ sketch: Sketch, reserved: Set<String> = []) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy) { reserved.contains($0) }
        model.choose(.dimension)
        return (model, RecordingHost(model))
    }

    func onlyDimension(_ model: SketchEditorModel) -> SketchDimension? {
        model.sketch.dimensionIDs.last.flatMap { model.sketch.dimensions[$0] }
    }

    @Test func aLineThenNothingIsItsLength() throws {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch)
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty, "a line waits for a second pick")
        #expect(model.overlay.lines.contains { $0.tint == .selected }, "the first pick is shown")
        model.click(at: Vector2(30, 20), tolerance: 1, modifiers: [])
        let dimension = try #require(onlyDimension(model))
        #expect(dimension.kind == .length(rectangle.lines[0]) && abs(dimension.value - 60) < 1e-9 && dimension.isDriving)
        #expect(host.commits.map(\.description) == ["Dimension d1"])
        #expect(model.solution.degreesOfFreedom == 1, "it holds the width, and nothing moved")
    }

    @Test func twoLinesAreAnAngleAndTwoPointsADistance() throws {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, _) = makeModel(rectangle.sketch)
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        model.click(at: Vector2(60.2, 20), tolerance: 1, modifiers: [])
        let angle = try #require(onlyDimension(model))
        #expect(angle.kind == .angle(rectangle.lines[0], rectangle.lines[1]) && abs(angle.value - 90) < 1e-6)
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        model.click(at: Vector2(60.2, 40.2), tolerance: 1, modifiers: [])
        let distance = try #require(onlyDimension(model))
        #expect(distance.kind == .distance(rectangle.corners[0], rectangle.corners[2]))
        #expect(abs(distance.value - Vector2(60, 40).length) < 1e-6)
    }

    @Test func aCircleIsItsDiameterAtOnce() throws {
        var sketch = Sketch()
        sketch.addCircle(center: Vector2(0, 0), radius: 5)
        let (model, host) = makeModel(sketch)
        model.click(at: Vector2(5.2, 0), tolerance: 1, modifiers: [])
        #expect(host.commits.count == 1)
        let dimension = try #require(onlyDimension(model))
        #expect(abs(dimension.value - 10) < 1e-9)
    }

    @Test func typedValuesDriveTheSketchAndNonsenseIsRefused() throws {
        let rectangle = RectangleSketch()
        let (model, host) = makeModel(rectangle.sketch)
        model.setValue("80 mm", of: rectangle.width)
        #expect(host.commits.map(\.description) == ["Change d1"])
        let corner = try #require(model.sketch.position(of: rectangle.corners[1]))
        #expect(abs(corner.x - 80) < 1e-6)
        #expect(model.dimensionRows.first?.value == "80 mm")
        model.setValue("wide", of: rectangle.width)
        #expect(model.refusal == "“wide” isn't a number." && host.commits.count == 1)
    }

    @Test func renamingRefusesTakenAndReservedNames() {
        let rectangle = RectangleSketch()
        let (model, host) = makeModel(rectangle.sketch, reserved: ["plane"])
        model.rename(rectangle.width, to: "d2")
        #expect(model.refusal == "Another dimension is already called “d2”.")
        model.rename(rectangle.width, to: "plane")
        #expect(model.refusal?.contains("taken by the Sketch node") == true)
        model.rename(rectangle.width, to: " width ")
        #expect(model.sketch.dimensions[rectangle.width]?.name == "width")
        #expect(host.commits.map(\.description) == ["Rename d1 to width"])
    }

    @Test func exposingAndReferenceAreOneStepEach() {
        let rectangle = RectangleSketch()
        let (model, host) = makeModel(rectangle.sketch)
        model.setExposed(true, of: rectangle.width)
        model.setDriving(false, of: rectangle.height)
        #expect(model.sketch.dimensions[rectangle.width]?.isExposed == true)
        #expect(model.dimensionRows.map(\.isDriving) == [true, false])
        #expect(host.commits.map(\.description) == ["Expose d1", "Make d2 Reference"])
        #expect(model.solution.degreesOfFreedom == 1, "a reference dimension holds nothing")
    }

    @Test func theInspectorListsAndRemovesConstraintsAndMarksConflicts() throws {
        var rectangle = RectangleSketch()
        let extra = rectangle.sketch.add(.vertical(rectangle.lines[0]))
        rectangle.sketch.dimensions[rectangle.width]?.isExposed = true
        let (model, host) = makeModel(rectangle.sketch)
        let row = try #require(model.constraintRows.first { $0.id == extra })
        #expect(row.isConflicting && row.label == "Vertical on Line 1")
        model.remove(.dimension(rectangle.width))
        #expect(host.commits.isEmpty && model.refusal?.contains("exposed as an input") == true)
        model.remove(.constraint(extra))
        #expect(host.commits.map(\.description) == ["Delete Vertical on Line 1"])
        #expect(model.statusText == "Fully constrained")
    }
}

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

    @Test func zeroNegativeAndOutOfRangeValuesAreRefused() {
        let rectangle = RectangleSketch()
        let (model, host) = makeModel(rectangle.sketch)
        for text in ["0", "0 mm", "-5 mm"] {
            model.refusal = nil
            model.setValue(text, of: rectangle.width)
            #expect(model.refusal == "A length must be more than 0 mm.")
        }
        #expect(host.commits.isEmpty)
        #expect(model.dimensionRows.first?.value == "60 mm")
    }

    @Test func anglesOutsideZeroTo180AreRefused() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0))
        let l1 = sketch.addLine(from: a, to: sketch.addPoint(Vector2(10, 0)))
        let l2 = sketch.addLine(from: a, to: sketch.addPoint(Vector2(0, 10)))
        let angle = sketch.addDimension(.angle(l1, l2), value: 90)
        let (model, host) = makeModel(sketch)
        for text in ["270°", "-10°", "181"] {
            model.refusal = nil
            model.setValue(text, of: angle)
            #expect(model.refusal == "An angle must be between 0° and 180°.")
        }
        #expect(host.commits.isEmpty)
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

    /// A reference dimension's row shows the live measurement, not the value it had when it became a reference, and
    /// its value can't be typed (it would change nothing). Making it driving again holds the geometry as it is.
    @Test func aReferenceRowFollowsTheGeometryAndRefusesTypedValues() throws {
        let rectangle = RectangleSketch()
        let (model, host) = makeModel(rectangle.sketch)
        model.setDriving(false, of: rectangle.height)
        model.choose(.select)
        #expect(model.beginDrag(at: Vector2(60, 40), tolerance: 1))
        model.endDrag(at: Vector2(60, 55))
        let measured = try #require(model.solution.measurements[rectangle.height])
        #expect(abs(measured - 55) < 1e-6)
        let row = try #require(model.dimensionRows.first { $0.id == rectangle.height })
        #expect(row.value == "55 mm" && !row.isValueEditable)
        model.setValue("20", of: rectangle.height)
        #expect(model.refusal == "d2 is a reference: make it driving to set it.")
        #expect(host.commits.map(\.description) == ["Make d2 Reference", "Move Point"])
        model.setDriving(true, of: rectangle.height)
        let corner = try #require(model.sketch.position(of: rectangle.corners[2]))
        #expect(abs(corner.y - 55) < 1e-6, "driving again holds the height as it is")
        #expect(model.dimensionRows.last?.value == "55 mm")
    }

    /// A dimension whose value comes from a wire (the host says which) can't be typed.
    @Test func aWiredDimensionRefusesTypedValues() throws {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy, wired: [rectangle.width])
        let host = RecordingHost(model)
        let row = try #require(model.dimensionRows.first)
        #expect(row.isWired && !row.isValueEditable)
        model.setValue("75", of: rectangle.width)
        #expect(model.refusal == "Its value comes from the wire into “d1”.")
        #expect(host.commits.isEmpty)
        model.reload(rectangle.sketch, plane: .xy, wired: [])
        #expect(model.dimensionRows.first?.isWired == false, "the host's reload says what's wired now")
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

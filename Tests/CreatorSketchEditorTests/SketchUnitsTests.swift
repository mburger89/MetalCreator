import CreatorGeometry
import CreatorSketch
import Foundation
import Testing
@testable import CreatorSketchEditor

/// The sketch editor speaks the document's unit: the inspector's values, what a typed value means, the refusals, the
/// pointer readout and the tool options. Values stay millimetres inside.
@MainActor
struct SketchUnitsTests {
    let inches = DocumentUnits(length: .inches)

    func makeModel(units: DocumentUnits) -> (SketchEditorModel, RectangleSketch) {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        model.units = units
        return (model, rectangle)
    }

    @Test func rowsShowValuesInTheDocumentsUnit() throws {
        let (model, rectangle) = makeModel(units: inches)
        #expect(model.dimensionRows.first?.value == "2.3622 in", "a driving row opens with its edit text")
        model.choose(.select)
        model.setDriving(false, of: rectangle.width)
        let reference = try #require(model.dimensionRows.first)
        #expect(reference.value == "2.36 in", "a reference row reads rounded to the precision")
        var sketch = rectangle.sketch
        let angle = sketch.addDimension(.angle(rectangle.lines[0], rectangle.lines[1]), value: 45, isDriving: true)
        let angled = SketchEditorModel(sketch: sketch, plane: .xy)
        angled.units = inches
        #expect(angled.dimensionRows.first { $0.id == angle }?.value == "45°")
    }

    @Test func aTypedValueFollowsTheUnitOrItsSuffix() throws {
        let (model, rectangle) = makeModel(units: inches)
        model.setValue("2", of: rectangle.width)
        #expect(abs(try #require(model.sketch.dimensions[rectangle.width]).value - 50.8) < 1e-9)
        model.setValue("50 mm", of: rectangle.width)
        #expect(abs(try #require(model.sketch.dimensions[rectangle.width]).value - 50) < 1e-9)
        let (millimetres, other) = makeModel(units: .millimetres)
        millimetres.setValue("2 in", of: other.width)
        #expect(abs(try #require(millimetres.sketch.dimensions[other.width]).value - 50.8) < 1e-9)
    }

    @Test func refusalsNameTheUnit() {
        let (model, rectangle) = makeModel(units: inches)
        model.setValue("0", of: rectangle.width)
        #expect(model.refusal == "A length must be more than 0 in.")
        model.setValue("1/2", of: rectangle.width)
        #expect(model.refusal == "“1/2” isn't a number.")
    }

    @Test func theReadoutSpeaksTheDocumentsUnit() {
        let line = SketchEditorModel(sketch: Sketch(), plane: .xy)
        line.units = inches
        line.choose(.line)
        line.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        line.hover(at: Vector2(24.5, 0.1), tolerance: 1, modifiers: [])
        #expect(line.pointerReadout == "0.96 in · 0.0°")
        let circle = SketchEditorModel(sketch: Sketch(), plane: .xy)
        circle.units = inches
        circle.choose(.circle)
        circle.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        circle.hover(at: Vector2(6, 8), tolerance: 1, modifiers: [])
        #expect(circle.pointerReadout == "Ø 0.79 in")
    }

    @Test func toolOptionsFollowTheUnit() {
        let (model, _) = makeModel(units: inches)
        #expect(model.lengthFieldText(25.4) == "1 in")
        model.setFilletRadius("0.25")
        #expect(abs(model.options.filletRadius - 6.35) < 1e-9)
        #expect(model.lengthFieldText(model.options.filletRadius) == "0.25 in")
        model.setPatternSpacing("1 in")
        #expect(abs(model.options.patternSpacing - 25.4) < 1e-9)
        model.setFilletRadius("0")
        #expect(model.refusal == "A fillet radius must be a number more than 0 in.")
        model.setPatternSpacing("-1")
        #expect(model.refusal == "A pattern spacing must be a number more than 0 in.")
        model.units = .millimetres
        #expect(model.lengthFieldText(2.5) == "2.5 mm")
    }
}

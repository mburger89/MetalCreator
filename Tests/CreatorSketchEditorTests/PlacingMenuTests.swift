import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// Right-click while a dimension is being placed (spec §4.2): Radius or Diameter, Driving or Reference.
@MainActor
struct PlacingMenuTests {
    let pendingID = SketchDimensionDrawing.pendingID
    let radius = HostMenuAction(title: "Radius", key: "dimension.radius")
    let diameter = HostMenuAction(title: "Diameter", key: "dimension.diameter")
    let driving = HostMenuAction(title: "Driving", key: "dimension.driving")
    let reference = HostMenuAction(title: "Reference", key: "dimension.reference")
    let anywhere = ScreenPoint(10, 10)

    @Test func aRadiusOffersDiameterAndReference() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(Vector2(0, 0))
        let arc = sketch.addArc(center: center, start: sketch.addPoint(Vector2(5, 0)), end: sketch.addPoint(Vector2(0, 5)))
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.dimension)
        model.click(at: Vector2(3.6, 3.6), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 20), tolerance: 1, modifiers: [])
        model.valueBoxClosed(pendingID, by: .unchanged)
        #expect(model.menuActions(at: anywhere) == [diameter, reference])
        model.performMenuAction(diameter)
        #expect(model.pending?.kind == .diameter(arc))
        #expect(try #require(model.pending?.value) == 10)
        #expect(model.menuActions(at: anywhere) == [radius, reference])
        model.performMenuAction(radius)
        #expect(model.pending?.kind == .radius(arc) && model.pending?.value == 5)
    }

    @Test func linearDimensionsOfferOnlyDrivingOrReference() {
        let (model, _) = pickedDiagonal(dimensioned: false)
        model.valueBoxClosed(pendingID, by: .unchanged)
        #expect(model.menuActions(at: anywhere) == [reference])
        model.performMenuAction(reference)
        #expect(model.pending?.isDriving == false)
        #expect(model.menuActions(at: anywhere) == [driving])
    }

    @Test func choosingReferencePlacesAReference() throws {
        let (model, host) = pickedDiagonal(dimensioned: false)
        model.valueBoxClosed(pendingID, by: .unchanged)
        model.performMenuAction(reference)
        model.click(at: Vector2(30, 20), tolerance: 1, modifiers: [])
        let dimension = try #require(model.sketch.dimensionIDs.last.flatMap { model.sketch.dimensions[$0] })
        #expect(!dimension.isDriving)
        #expect(host.commits.count == 1)
    }

    @Test func makingAnOverDefiningOneDrivingIsRefused() {
        let (model, _) = pickedDiagonal(dimensioned: true)
        #expect(model.pending?.phase == .placing && model.pending?.isDriving == false)
        #expect(model.menuActions(at: anywhere) == [driving])
        model.performMenuAction(driving)
        #expect(model.pending?.isDriving == false)
        #expect(model.refusal == "That would over-define the sketch.")
    }

    @Test func noMenuWhenNotPlacing() {
        let rectangle = RectangleSketch(dimensioned: false)
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        model.choose(.dimension)
        #expect(model.menuActions(at: anywhere).isEmpty)
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        model.click(at: Vector2(60.2, 40.2), tolerance: 1, modifiers: [])
        #expect(model.pending?.phase == .entering)
        #expect(model.menuActions(at: anywhere).isEmpty)
    }

    func pickedDiagonal(dimensioned: Bool) -> (SketchEditorModel, RecordingHost) {
        let rectangle = RectangleSketch(dimensioned: dimensioned)
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        model.choose(.dimension)
        let host = RecordingHost(model)
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        model.click(at: Vector2(60.2, 40.2), tolerance: 1, modifiers: [])
        return (model, host)
    }
}

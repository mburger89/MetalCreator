import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The preview in the window (fields spec §6): a selected field node tints the part and shows the slice and its handle; the
/// legend's state is the model's. What it looks like is a human check (group FI).
@MainActor
struct AppFieldPreviewTests {
    /// A 20 × 10 × 10 box into an Output, a Radial Gradient (radius 10) and a Sample Field wired to the gradient.
    struct Scene {
        var builder = GraphBuilder()
        let box: (rectangle: Node, extrude: Node, output: Node)
        let radial: Node
        let sample: Node

        init() {
            let rectangle = builder.add(RectangleNode.self, ["width": .number(20)])
            let extrude = builder.add(ExtrudeNode.self, ["distance": .number(10)])
            let output = builder.add(OutputNode.self)
            builder.wire(rectangle, "profile", to: extrude, "profile")
            builder.wire(extrude, "solid", to: output, "solid")
            box = (rectangle, extrude, output)
            radial = builder.add(RadialGradientNode.self, ["radius": .number(10)])
            sample = builder.add(SampleFieldNode.self)
            builder.wire(radial, "field", to: sample, "field")
        }
    }

    func open() async -> (AppModel, Scene) {
        let scene = Scene()
        let app = await makeApp(scene.builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        return (app, scene)
    }

    @Test func aSelectedFieldNodeTintsThePartAndShowsTheSliceAndItsHandle() async throws {
        let (app, scene) = await open()
        #expect(app.viewport.items.count == 1 && app.viewport.items[0].fieldValues == nil && app.viewport.slice == nil)
        app.editor.selection = [scene.radial.id]
        await app.settle()
        let item = try #require(app.viewport.items.first)
        let mesh = try #require(app.viewport.displayMesh(of: item.solid))
        #expect(item.fieldValues?.count == mesh.positions.count)
        let colors = app.themes.current.colors
        #expect(item.fieldRamp?.low == colors.fieldLow.rgba && item.fieldRamp?.high == colors.fieldHigh.rgba)
        #expect(app.viewport.slice != nil && app.viewport.slice?.isValid == true)
        #expect(app.viewport.handles.map(\.id) == [FieldPreviewModel.sliceHandleID])
        #expect(app.fieldPreview.legend?.range != nil)
        #expect(app.document.previewNode == scene.radial.id, "the field node is evaluated though nothing downstream is wired")
    }

    @Test func aNodeThatTakesAFieldPreviewsTheOneWiredIntoIt() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.sample.id]
        await app.settle()
        #expect(app.viewport.items.first?.fieldValues != nil && app.viewport.slice != nil)
    }

    @Test func selectingSomethingElseOrNothingTakesThePreviewAway() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        app.editor.selection = [scene.box.extrude.id]
        await app.settle()
        #expect(app.viewport.items.first?.fieldValues == nil && app.viewport.slice == nil)
        #expect(!app.viewport.handles.contains { $0.id == FieldPreviewModel.sliceHandleID }, "the Extrude's own handle remains")
        #expect(app.fieldPreview.legend == nil)
        app.editor.selection = [scene.radial.id]
        await app.settle()
        app.editor.selection = []
        await app.settle()
        #expect(app.viewport.items.first?.fieldValues == nil && app.viewport.slice == nil && app.fieldPreview.node == nil)
    }

    @Test func anEditToTheFieldRetintsThePart() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        let before = try #require(app.viewport.items.first?.fieldValues)
        try app.document.perform(.setInput(scene.radial.id, "radius", .number(20)))
        await app.settle()
        let after = try #require(app.viewport.items.first?.fieldValues)
        #expect(after != before && after.count == before.count)
    }

    @Test func aThemeChangeRecoloursTheTintWithoutSamplingAgain() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        let values = app.viewport.items.first?.fieldValues
        app.themes.select("nord")
        await app.settle()
        #expect(app.viewport.items.first?.fieldRamp?.low == ColorTheme.nord.colors.fieldLow.rgba)
        #expect(app.viewport.items.first?.fieldValues == values)
    }

    @Test func theLegendsToggleChangesTheRampAndTheSliceHandleEditsNoDocument() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        let revision = app.document.undoName
        app.fieldPreview.setUnitRange(true)
        await app.settle()
        #expect(app.viewport.items.first?.fieldRamp?.lowValue == 0 && app.viewport.items.first?.fieldRamp?.highValue == 1)
        app.handleChanged(FieldPreviewModel.sliceHandleID, 2, .changed)
        await app.settle()
        #expect(app.fieldPreview.offset == 2 && app.viewport.handles.first?.value == 2)
        #expect(app.viewport.slice?.origin.z == (app.fieldPreview.bounds?.center.z ?? 0) + 2)
        app.handleChanged(FieldPreviewModel.sliceHandleID, 3, .ended)
        #expect(app.document.undoName == revision && !app.isEdited, "view state: not an edit, not an undo step")
    }

    @Test func theHandleAndTheSliceGoWithTheLegendsHideButton() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        app.fieldPreview.chooseSlice(.hidden)
        await app.settle()
        #expect(app.viewport.slice == nil && app.viewport.handles.isEmpty)
        #expect(app.viewport.items.first?.fieldValues != nil, "the tint stays")
    }

    @Test func aPickInProgressTakesThePreviewAwayAndEndingItBringsItBack() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        let solid = try #require(app.viewport.items.first?.solid)
        let source = try #require(app.producer(of: solid))
        app.pick = PickSession(solid: solid, source: source, rule: nil, consumer: nil, picked: [])
        await app.settle()
        #expect(app.fieldPreview.node == nil && app.viewport.slice == nil)
        #expect(app.viewport.items.allSatisfy { $0.fieldValues == nil })
        app.pick = nil
        await app.settle()
        #expect(app.viewport.items.first?.fieldValues != nil && app.viewport.slice != nil)
    }

    @Test func openingAnotherDocumentStartsThePreviewOver() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        app.load(GraphFile(), from: nil)
        await app.settle()
        #expect(app.fieldPreview.node == nil && app.viewport.slice == nil && app.viewport.items.isEmpty)
    }

    @Test func aFieldNodeInSelectedNodeModeWithNoPartHasNothingToTint() async throws {
        let (app, scene) = await open()
        app.previewMode = .selectedNode
        app.editor.selection = [scene.radial.id]
        await app.settle()
        #expect(app.viewport.items.isEmpty && app.viewport.slice == nil && app.fieldPreview.legend == nil)
    }
}

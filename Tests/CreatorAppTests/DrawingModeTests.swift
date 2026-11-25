import CreatorDrawing
import CreatorDrawingEditor
@testable import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// Drawing mode in the app (drawings plan R4, R21, R28).
/// What of the model's chrome the window shows.
struct Shown {
    var section, zebra, measure, badge, chip, preview, analysis: Bool
}

@MainActor
struct DrawingModeTests {
    func control(_ label: String, in app: AppWindow) throws -> [TestElement] {
        try app.window.elements { $0.label == label && $0.role != .staticText }
    }

    func open(_ box: DrawingBox = DrawingBox()) async throws -> AppWindow {
        try await AppWindow.open(box.graph)
    }

    func enterDrawing(_ app: AppWindow) async throws {
        app.model.setMode(.drawing)
        await app.model.settle()
        try await app.window.runUntilIdle()
    }

    @Test func theSwitchShowsTheSheet() async throws {
        let app = try await open()
        #expect(try control("Add Sheet", in: app).isEmpty, "the model area shows the viewport")
        try await enterDrawing(app)
        #expect(app.model.mode == .drawing)
        #expect(try control("Add Sheet", in: app).count >= 1, "the model area shows the sheet canvas")
        app.model.setMode(.model)
        try await app.window.runUntilIdle()
        #expect(try control("Add Sheet", in: app).isEmpty)
    }

    @Test func theTopBarSwitchChoosesTheMode() async throws {
        let app = try await open()
        try app.window.click(try #require(try app.window.elements { $0.label == "Drawing" }.first))
        try await app.window.runUntilIdle()
        #expect(app.model.mode == .drawing)
        try app.window.click(try #require(try app.window.elements { $0.label == "Model" }.first))
        try await app.window.runUntilIdle()
        #expect(app.model.mode == .model)
    }

    @Test func commandShiftDTogglesTheMode() async throws {
        let app = try await open()
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey("d", modifierFlags: [.primary, .shift])
        try await app.window.runUntilIdle()
        #expect(app.model.mode == .drawing)
        app.window.typeKey("d", modifierFlags: [.primary, .shift])
        try await app.window.runUntilIdle()
        #expect(app.model.mode == .model)
    }

    @Test func commandShiftDOverTheCanvasTogglesTheModeAndDuplicatesNothing() async throws {
        let box = DrawingBox()
        let app = try await open(box)
        app.editor.selection = [box.rectangle.id]
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        #expect(app.editor.pointerLocation != nil)
        let nodes = app.editor.graph.nodes.count
        let steps = app.model.document.undoName
        app.window.typeKey("d", modifierFlags: [.primary, .shift])
        try await app.window.runUntilIdle()
        #expect(app.model.mode == .drawing)
        #expect(app.editor.graph.nodes.count == nodes, "nothing was duplicated")
        #expect(app.model.document.undoName == steps, "and no undo step was made")
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        app.window.typeKey("d", modifierFlags: [.primary, .shift])
        try await app.window.runUntilIdle()
        #expect(app.model.mode == .model)
        #expect(app.editor.graph.nodes.count == nodes)
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        app.window.typeKey("d", modifierFlags: .primary)
        #expect(app.editor.graph.nodes.count == nodes + 1, "⌘D alone still duplicates")
    }

    @Test func enteringEndsModelTools() async throws {
        let app = await makeApp(DrawingBox().graph)
        app.setMeasure(true)
        #expect(app.measure != nil)
        app.setMode(.drawing)
        #expect(app.measure == nil && app.pick == nil && app.sketch == nil && app.modelDimension == nil && app.controlNet == nil)
        app.setMode(.model)
        #expect(app.beginModelDimension())
        app.setMode(.drawing)
        #expect(app.modelDimension == nil)
    }

    @Test func anOpenSketchIsFinishedOnEntering() async throws {
        var builder = GraphBuilder()
        let sketch = builder.add(SketchNode.self)
        let app = await makeApp(builder.graph)
        app.beginSketch(for: sketch.id)
        await app.settle()
        try #require(app.sketch != nil)
        app.setMode(.drawing)
        #expect(app.sketch == nil)
    }

    @Test func aPickingSessionIsCancelledOnEntering() async throws {
        let box = DrawingBox()
        var builder = box.builder
        let rule = builder.add(EdgesByTagNode.self)
        builder.wire(box.extrude, "solid", to: rule, "solid")
        let app = await makeApp(builder.graph)
        app.beginPick(for: rule.id)
        try #require(app.pick != nil)
        app.setMode(.drawing)
        #expect(app.pick == nil)
    }

    @Test func aPickButtonSwitchesBackToModel() async throws {
        let box = DrawingBox()
        var builder = box.builder
        let rule = builder.add(EdgesByTagNode.self)
        builder.wire(box.extrude, "solid", to: rule, "solid")
        let app = await makeApp(builder.graph)
        app.setMode(.drawing)
        await app.settle()
        app.handle(InspectorRequest(node: rule.id, action: .pickEdgesInView, serial: 1))
        #expect(app.mode == .model)
        #expect(app.pick != nil, "and then the pick runs")
    }

    @Test func viewportKeysDoNothingInDrawing() async throws {
        let app = await makeApp(DrawingBox().graph)
        let input = AppInput(model: app)
        app.setMode(.drawing)
        #expect(!input.handleAction(MeasureKeyAction()))
        #expect(!input.handleAction(ZebraKeyAction()))
        #expect(!input.handleAction(ModelDimensionKeyAction()))
        #expect(app.measure == nil && app.document.zebra?.isOn != true && app.modelDimension == nil)
        app.setMode(.model)
        #expect(input.handleAction(ZebraKeyAction()), "in Model the same key answers")
    }

    @Test func noSheetShowsAddSheetAndEnteringIsNotAnEdit() async throws {
        let app = try await open()
        let before = app.model.document.undoName
        try await enterDrawing(app)
        #expect(app.model.drawing.editor.document.sheets.isEmpty && app.model.document.drawings.isEmpty)
        #expect(try control("Add Sheet", in: app).count >= 1)
        #expect(!app.model.isEdited && app.model.document.undoName == before, "entering adds nothing")
        app.model.setMode(.model)
        #expect(!app.model.isEdited && app.model.document.undoName == before)
        #expect(app.model.document.drawingView == nil, "and a document that never drew stays as it was")
    }

    @Test func theModeAndSheetAreSavedAsViewState() async throws {
        let app = await AppModel.inDrawing(DrawingBox().graph)
        app.drawing.editor.addSheet()
        let second = try #require(app.drawing.editor.currentSheet)
        app.drawing.editor.selectSheet(app.drawing.editor.document.sheets[0].id)
        let first = try #require(app.drawing.editor.currentSheet)
        #expect(first != second)
        #expect(app.document.drawingView == DrawingViewState(isOn: true, sheet: first), "switching is view state")
        let url = temporaryURL("drawn.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        let reopened = await makeApp()
        try reopened.open(url)
        await reopened.settle()
        #expect(reopened.mode == .drawing)
        #expect(reopened.drawing.editor.currentSheet == first)
        #expect(reopened.drawing.editor.document.sheets.count == 2)
        #expect(!reopened.isEdited, "the mode isn't an edit")
        reopened.setMode(.model)
        #expect(!reopened.isEdited)
    }

    @Test func switchingModeOrSheetIsNoUndoStep() async throws {
        let app = await AppModel.inDrawing(DrawingBox().graph)
        let name = app.document.undoName
        app.drawing.editor.addSheet()
        #expect(app.document.undoName == "Add Sheet")
        app.drawing.editor.selectSheet(app.drawing.editor.document.sheets[0].id)
        app.setMode(.model)
        app.setMode(.drawing)
        #expect(app.document.undoName == "Add Sheet", "still the last real step")
        _ = name
    }

    @Test func theInspectorShowsTheDrawingInspector() async throws {
        let app = try await open()
        app.model.setMode(.drawing)
        app.model.drawing.editor.addSheet()
        await app.model.settle()
        try await app.window.runUntilIdle()
        let block = try app.window.elements { $0.label == "TITLE BLOCK" || $0.value == "TITLE BLOCK" }
        #expect(block.count == 1, "the sheet's title block fields are in the inspector")
        app.model.setMode(.model)
        try await app.window.runUntilIdle()
        #expect(try app.window.elements { $0.label == "TITLE BLOCK" || $0.value == "TITLE BLOCK" }.isEmpty)
    }

    @Test func drawingModeHidesTheModelOverlays() async throws {
        var builder = DrawingBox()
        builder.builder.graph.nodes[builder.output.id]?.name = "Out"
        let sphere = builder.builder.add(ImplicitSphereNode.self, ["radius": .number(6)])
        let mesh = builder.builder.add(MeshNode.self, ["preview resolution": .number(1)])
        let meshOutput = builder.builder.add(OutputNode.self)
        builder.builder.wire(sphere, "implicit", to: mesh, "implicit")
        builder.builder.wire(mesh, "mesh", to: meshOutput, "mesh")
        let app = try await AppWindow.open(builder.graph)
        try await app.chooseAnalysis("Section")
        try await app.chooseAnalysis("Zebra")
        try await app.chooseAnalysis("Measure")
        let gate = WaitGate()
        gate.open()
        app.model.slowEvaluation.wait = { try await gate.wait($0) }
        app.model.slowEvaluation.follow(running: true, names: ["Fillet"])
        await app.model.slowEvaluation.waitForTimer()
        try await app.window.runUntilIdle()
        func shown() throws -> Shown {
            let labels = try app.window.elements { _ in true }
            let has: (String) -> Bool = { text in labels.contains { $0.label == text || $0.value == text } }
            return Shown(section: has("Offset"), zebra: has("Lock stripes to the part"), measure: has("Keep"),
                         badge: has("Preview 1 mm"), chip: has("Building Fillet…"), preview: has("Preview"), analysis: has("Analysis"))
        }
        let model = try shown()
        #expect(model.section && model.zebra && model.measure && model.badge && model.chip && model.preview && model.analysis, "\(model)")
        let edited = app.model.isEdited
        try await enterDrawing(app)
        let drawing = try shown()
        #expect(!drawing.section && !drawing.zebra && !drawing.measure && !drawing.badge, "no Section, Zebra or Measure panel, no badge")
        #expect(!drawing.preview && !drawing.analysis, "no Preview picker, no Analysis menu")
        #expect(drawing.chip, "the slow-evaluation chip still shows")
        #expect(app.model.document.section?.isOn == true && app.model.document.zebra?.isOn == true)
        app.model.setMode(.model)
        try await app.window.runUntilIdle()
        let back = try shown()
        #expect(back.section && back.zebra && back.badge && back.chip && back.preview && back.analysis, "\(back)")
        #expect(app.model.isEdited == edited, "none of it was an edit")
    }

    @Test func theViewMenuDisablesTheViewportItemsInDrawing() async throws {
        let app = try await open()
        func item(_ title: String) throws -> PlatformMenuItem {
            let view = try #require(app.testApp.menuBar.first { $0.title == "View" })
            return try #require(view.items.first { $0.title == title })
        }
        #expect(try item("Show Section").isEnabled && item("Measure").isEnabled && item("Show Zebra Stripes").isEnabled)
        #expect(try item("Drawing").isEnabled && !item("Model").isEnabled)
        try await enterDrawing(app)
        #expect(try !item("Show Section").isEnabled && !item("Measure").isEnabled && !item("Show Zebra Stripes").isEnabled)
        #expect(try item("Drawing").isEnabled && item("Model").isEnabled, "⌘⇧D stays live to toggle back")
    }
}

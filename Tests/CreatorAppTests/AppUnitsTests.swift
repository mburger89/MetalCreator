import CreatorGeometry
import CreatorKernel
import CreatorGraph
import CreatorSketch
import CreatorViewport
import Foundation
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor

/// Choosing units and precision (DIM-1, spec §6): one undoable document setting, remembered for new documents, saved with the file.
@MainActor
struct AppUnitsTests {
    /// One 60 mm line on XY with its length dimension.
    func lineSketch() -> (sketch: Sketch, dimension: DimensionID) {
        var sketch = Sketch(plane: .fixed(.xy))
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(60, 0))
        let line = sketch.addLine(from: a, to: b)
        sketch.add(.fix(a, at: .zero))
        sketch.add(.horizontal(line))
        let dimension = sketch.addDimension(.length(line), value: 60)
        return (sketch, dimension)
    }

    /// An app with the sketch open, settled.
    func sketching() async -> (app: AppModel, dimension: DimensionID) {
        let (sketch, dimension) = lineSketch()
        var builder = GraphBuilder()
        let box = builder.sketchedBox(sketch)
        let app = await makeApp(builder.graph)
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        return (app, dimension)
    }

    @Test func choosingInchesIsOneUndoStepAndAnEdit() async {
        let (app, _) = await sketching()
        let edited = app.isEdited
        app.setUnits(.inches)
        await app.settle()
        #expect(app.units == DocumentUnits(length: .inches))
        #expect(app.undoTitle == "Undo Change Units")
        #expect(app.isEdited != edited)
        #expect(app.sketch?.editor.units == DocumentUnits(length: .inches))
        app.undo()
        #expect(app.units == .millimetres)
        #expect(!app.document.canUndo, "one step")
    }

    @Test func choosingTheSameUnitChangesNothing() async {
        let app = await makeApp()
        app.setUnits(.millimetres)
        #expect(app.document.undoName == nil)
        #expect(!app.isEdited)
    }

    @Test func undoGivesTheOpenSketchItsUnitsBack() async {
        let (app, _) = await sketching()
        app.setUnits(.inches)
        await app.settle()
        #expect(app.sketch?.editor.units.length == .inches)
        app.undo()
        await app.settle()
        #expect(app.sketch?.editor.units == .millimetres)
        app.redo()
        await app.settle()
        #expect(app.sketch?.editor.units.length == .inches)
    }

    @Test func aNewDocumentUsesTheLastUnitChosen() async {
        let preference = InMemoryUnitPreference(lastLength: .inches)
        let app = AppModel(kernel: FakeKernel(), unitPreference: preference)
        await app.settle()
        #expect(app.units == .millimetres, "the first document is the one given")
        app.newDocument()
        await app.settle()
        #expect(app.units == DocumentUnits(length: .inches))
        #expect(!app.isEdited)
        #expect(!app.document.canUndo)
    }

    @Test func choosingAUnitIsRememberedForNewDocuments() async {
        let preference = InMemoryUnitPreference()
        let app = AppModel(kernel: FakeKernel(), unitPreference: preference)
        app.setUnits(.inches)
        #expect(preference.lastLength == .inches)
        app.keepChanges()
        app.newDocument()   // edited: asks first
        #expect(app.alert == .discardChanges)
        await app.discardChanges()
        #expect(app.units.length == .inches)
        #expect(!app.isEdited)
    }

    @Test func aUnitChangeClosesAnOpenValueBox() async throws {
        let (app, dimension) = await sketching()
        let id = SketchDimensionDrawing.overlayID(dimension)
        try #require(app.viewport.openValueBox(for: id))
        app.setUnits(.inches)
        #expect(app.viewport.valueBox == nil)
        let editor = try #require(app.sketch?.editor)
        #expect(editor.sketch.dimensions[dimension]?.value == 60, "nothing was committed")
        #expect(app.undoTitle == "Undo Change Units")
    }

    @Test func aPrecisionChangeClosesAnOpenValueBox() async throws {
        let (app, dimension) = await sketching()
        try #require(app.viewport.openValueBox(for: SketchDimensionDrawing.overlayID(dimension)))
        app.setPrecision(3)
        #expect(app.viewport.valueBox == nil)
        #expect(app.undoTitle == "Undo Change Precision")
    }

    @Test func theDefaultPrecisionStoresNoKey() async {
        let app = await makeApp()
        app.setPrecision(3)
        #expect(app.document.units.precision == 3)
        app.setPrecision(1)   // millimetres' default
        #expect(app.document.units.precision == nil)
        #expect(app.document.units == .millimetres)
        app.setUnits(.inches)
        app.setPrecision(2)   // inches' default
        #expect(app.document.units.precision == nil)
    }

    @Test func aUnitChangeStartsAtTheNewUnitsDefaultPrecision() async {
        let app = await makeApp()
        app.setPrecision(3)
        app.setUnits(.inches)   // the brief: `.setUnits(DocumentUnits(length:))`
        #expect(app.units == DocumentUnits(length: .inches))
        #expect(app.units.fractionDigits == 2)
    }

    @Test func savedUnitsReopen() async throws {
        let app = await makeApp()
        app.setUnits(.inches)
        app.setPrecision(3)
        let url = temporaryURL("units.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        let reopened = await makeApp()
        try reopened.open(url)
        await reopened.settle()
        #expect(reopened.units == DocumentUnits(length: .inches, precision: 3))
        #expect(!reopened.isEdited)
    }

    @Test func theDefaultsRememberTheUnit() throws {
        let name = "AppUnitsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = UserDefaultsUnitPreference(defaults: defaults)
        #expect(preference.lastLength == .millimetres)
        preference.lastLength = .inches
        #expect(UserDefaultsUnitPreference(defaults: defaults).lastLength == .inches)
        #expect(defaults.string(forKey: "MetalCreator.lastLengthUnit") == "in")
        defaults.set("furlongs", forKey: UserDefaultsUnitPreference.key)
        #expect(preference.lastLength == .millimetres)
    }

    @Test func theMenusListUnitsAndPrecisions() async {
        let app = await makeApp()
        let units = MenuEvaluation { UnitsMenu.unitItems(app) }
        #expect(units.items.map(\.title) == ["Millimetres", "Inches"])
        #expect(units.items.filter(\.isOn).map(\.title) == ["Millimetres"])
        let precisions = MenuEvaluation { UnitsMenu.precisionItems(app) }
        #expect(precisions.items.map(\.title) == ["1", "0.1", "0.01", "0.001", "0.0001"])
        #expect(precisions.items.filter(\.isOn).map(\.title) == ["0.1"])
        app.setUnits(.inches)
        #expect(MenuEvaluation { UnitsMenu.precisionItems(app) }.items.filter(\.isOn).map(\.title) == ["0.01"])
    }

    @Test func choosingFromTheMenuChangesTheUnits() async throws {
        let app = await makeApp()
        try MenuEvaluation { UnitsMenu.unitItems(app) }.perform("Inches")
        #expect(app.units.length == .inches)
        try MenuEvaluation { UnitsMenu.precisionItems(app) }.perform("0.001")
        #expect(app.units.precision == 3)
    }
}

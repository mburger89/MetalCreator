import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// What the inspector shows for no sheet, no selection, one view and several (plan R22), and what the canvas's keys and empty
/// state say.
@MainActor
@Suite("Drawing inspector and canvas input")
struct DrawingInspectorTests {
    private func harness() -> (EditorHarness, [DrawingView]) {
        let views = [EditorDocuments.view(at: Vector2(100, 100)), EditorDocuments.view(at: Vector2(200, 100))]
        let sheet = DrawingSheet(name: "Sheet 1", views: views)
        return (EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id), views)
    }

    @Test func noSheetSaysSo() async throws {
        let model = EditorHarness(document: EditorDocuments.document([]), sheet: nil).model
        let window = try await DrawingWindow.open(scaleFactor: 1) { DrawingInspector(model: model) }
        #expect(try window.window.elements(role: .staticText).count == 1)
    }

    @Test func noSelectionShowsTheSheet() async throws {
        let (h, _) = harness()
        let window = try await DrawingWindow.open(size: Size(width: Pixels(400), height: Pixels(900)), scaleFactor: 1) {
            DrawingInspector(model: h.model)
        }
        #expect(try window.window.elements(role: .staticText).count > 8, "the sheet's rows")
    }

    @Test func severalViewsOfferDelete() async throws {
        let (h, views) = harness()
        h.model.selection = Set(views.map(\.id))
        let window = try await DrawingWindow.open(scaleFactor: 1) { DrawingInspector(model: h.model) }
        let delete = try window.window.element(label: "Delete")
        window.window.click(at: Point(x: delete.frame.origin.x + 4, y: delete.frame.origin.y + 4))
        #expect(h.log.commits.map(\.name) == ["Delete View"])
    }

    @Test func oneViewShowsItsControlsAndAToggleIsOneStep() async throws {
        let (h, views) = harness()
        h.model.selection = [views[0].id]
        let window = try await DrawingWindow.open(size: Size(width: Pixels(400), height: Pixels(600)), scaleFactor: 1) {
            DrawingInspector(model: h.model)
        }
        let toggle = try window.window.element(label: "Hidden lines")
        window.window.click(at: Point(x: toggle.frame.origin.x + 4, y: toggle.frame.origin.y + 4))
        #expect(h.log.commits.map(\.name) == ["Change View"])
        #expect(h.model.document.sheets[0].views.first { $0.id == views[0].id }?.showsHidden == true)
    }

    @Test func theKeysMapToDrawingKeys() {
        #expect(SheetCanvasInput.key("f", modifiers: []) == .fit)
        #expect(SheetCanvasInput.key(.delete, modifiers: []) == .delete)
        #expect(SheetCanvasInput.key(.deleteForward, modifiers: []) == .delete)
        #expect(SheetCanvasInput.key(.escape, modifiers: []) == .escape)
        #expect(SheetCanvasInput.key(.leftArrow, modifiers: []) == .nudge(Vector2(-1, 0)))
        #expect(SheetCanvasInput.key(.upArrow, modifiers: .shift) == .nudge(Vector2(0, 10)))
        #expect(SheetCanvasInput.key(.downArrow, modifiers: []) == .nudge(Vector2(0, -1)))
        #expect(SheetCanvasInput.key("x", modifiers: []) == nil)
    }

    @Test func theEmptyCanvasAddsASheetOnlyWhenAsked() async throws {
        let h = EditorHarness(document: EditorDocuments.document([]), sheet: nil)
        let window = try await DrawingWindow.open { SheetCanvas(model: h.model) }
        #expect(h.log.commits.isEmpty, "entering adds nothing")
        _ = try window.window.element(label: "No sheets yet")
        let button = try window.window.element(label: "Add Sheet")
        window.window.click(at: Point(x: button.frame.origin.x + 4, y: button.frame.origin.y + 4))
        #expect(h.log.commits.map(\.name) == ["Add Sheet"])
    }
}

/// The scale menu's Custom… and the density field's refusals (task 11 fix round 1).
@MainActor
@Suite("Drawing inspector scale and density")
struct DrawingInspectorScaleDensityTests {
    private func harness() -> (EditorHarness, DrawingView) {
        let view = EditorDocuments.view(at: Vector2(100, 100))
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        return (EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id), view)
    }

    @Test func customOnAViewUsingTheSheetsScaleShowsTheFields() {
        let custom = ScaleControl.selectedIndex(current: nil, isCustom: true, allowsSheetScale: true)
        #expect(custom == ScaleControl(current: nil, allowsSheetScale: true, standard: .iso) { _ in }.options.count - 1)
        #expect(ScaleControl.selectedIndex(current: nil, isCustom: false, allowsSheetScale: true) == 0)
    }

    @Test func aTypedScaleOnAViewIsOneStep() {
        let (h, view) = harness()
        h.model.setScale(DrawingScale(numerator: 1, denominator: 3), of: view.id)
        #expect(h.model.document.sheets[0].views[0].scale == DrawingScale(numerator: 1, denominator: 3))
        #expect(ScaleControl.selectedIndex(current: DrawingScale(numerator: 1, denominator: 3), isCustom: false, allowsSheetScale: true)
            == ScaleControl(current: nil, allowsSheetScale: true, standard: .iso) { _ in }.options.count - 1)
    }

    @Test func aDensityThatIsNotAPositiveFiniteNumberIsRefused() {
        let (h, _) = harness()
        h.model.setDensity(text: "7.85")
        #expect(h.model.document.sheets[0].titleBlock.density == 7.85)
        let steps = h.log.commits.count
        for bad in ["7,85", "abc", "inf", "1e400", "-1", "0"] {
            h.model.setDensity(text: bad)
            #expect(h.model.refusal != nil, "\(bad)")
            #expect(h.model.document.sheets[0].titleBlock.density == 7.85, "\(bad)")
        }
        #expect(h.log.commits.count == steps)
        h.model.setDensity(text: "")
        #expect(h.model.document.sheets[0].titleBlock.density == nil)
    }
}

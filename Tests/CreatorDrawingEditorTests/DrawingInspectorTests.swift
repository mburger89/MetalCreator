import CreatorGeometry
import CreatorKernel
import Foundation
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

    /// A parent top view and a derived view of `kind` made from it, the derived one selected.
    private func derived(_ kind: ViewKind, cutter: SectionCutter? = nil) -> (EditorHarness, DrawingView) {
        let parent = EditorDocuments.view(at: Vector2(100, 105), orientation: .top)
        let line = cutter ?? SectionCutter(
            frame: StandardOrientation.top.frame, points: [Vector2(5, 10), Vector2(20, 10), Vector2(20, 14), Vector2(35, 14)],
            viewing: Vector2(0, 1))
        let derivation: ViewDerivation = switch kind {
        case .detail: .detail(DetailCircle(parent: parent.id, center: Vector2(20, 10), radius: 6))
        case .auxiliary:
            .auxiliary(
                AuxiliaryArrow(
                    parent: parent.id, parentFrame: parent.orientation.frame, at: Vector2(20, 10), viewing: Vector2(0, 1)))
        default: .section(SectionLine(parent: parent.id, cutter: line))
        }
        let view = DrawingView(
            kind: kind, source: parent.source, orientation: parent.orientation, scale: DrawingScale(numerator: 2, denominator: 1),
            center: Vector2(220, 105), showsLabel: true, derivation: derivation, letter: "A")
        let sheet = DrawingSheet(name: "Sheet 1", views: [parent, view])
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.selection = [view.id]
        return (h, view)
    }

    private func texts(_ model: DrawingEditorModel) async throws -> [String] {
        let window = try await DrawingWindow.open(size: Size(width: Pixels(400), height: Pixels(700)), scaleFactor: 1) {
            DrawingInspector(model: model)
        }
        return try window.window.elements(role: .staticText).compactMap { $0.value ?? $0.label }
    }

    @Test func aSectionPageShowsItsTitleAndCut() async throws {
        let (h, _) = derived(.section)
        let shown = try await texts(h.model)
        #expect(shown.contains("Section A-A"), "\(shown)")
        #expect(shown.contains("Stepped (2 cuts)"), "\(shown)")
        #expect(!shown.contains("Source") && !shown.contains("Orientation"), "\(shown)")
        #expect(shown.contains("Scale"))
        let straight = derived(.section, cutter: SectionCutter(
            frame: StandardOrientation.top.frame, points: [Vector2(5, 10), Vector2(35, 10)], viewing: Vector2(0, 1)))
        #expect(try await texts(straight.0.model).contains("Straight"))
    }

    @Test func aDetailPageEditsItsRadius() async throws {
        let (h, view) = derived(.detail)
        let shown = try await texts(h.model)
        #expect(shown.contains("Detail A"), "\(shown)")
        #expect(shown.contains("Radius"), "\(shown)")
        #expect(!shown.contains("Source") && !shown.contains("Orientation"))
        h.model.setDetailRadius(8, of: view.id)
        #expect(h.log.commits.map(\.name) == ["Change Detail Circle"])
        guard case .detail(let circle)? = h.model.document.sheets[0].view(view.id)?.derivation else {
            Issue.record("not a detail")
            return
        }
        #expect(circle.radius == 8)
    }

    @Test func anAuxiliaryPageShowsItsTitle() async throws {
        let (h, _) = derived(.auxiliary)
        let shown = try await texts(h.model)
        #expect(shown.contains("View A"), "\(shown)")
        #expect(shown.contains("Scale") && !shown.contains("Source") && !shown.contains("Radius"), "\(shown)")
    }

    @Test func theKeysMapToDrawingKeys() {
        #expect(SheetCanvasInput.key("f", modifiers: []) == .fit)
        #expect(SheetCanvasInput.key(.delete, modifiers: []) == .delete)
        #expect(SheetCanvasInput.key(.deleteForward, modifiers: []) == .delete)
        #expect(SheetCanvasInput.key(.escape, modifiers: []) == .escape)
        #expect(SheetCanvasInput.key(.leftArrow, modifiers: []) == .nudge(Vector2(-1, 0), isRepeat: false))
        #expect(SheetCanvasInput.key(.upArrow, modifiers: .shift) == .nudge(Vector2(0, 10), isRepeat: false))
        #expect(SheetCanvasInput.key(.downArrow, modifiers: []) == .nudge(Vector2(0, -1), isRepeat: false))
        #expect(SheetCanvasInput.key("x", modifiers: []) == nil)
    }

    @Test func chordsWithCommandControlOrOptionFallThroughToTheMenus() {
        for held in [EventModifiers.primary, .control, .option] {
            #expect(SheetCanvasInput.key(.delete, modifiers: held) == nil)
            #expect(SheetCanvasInput.key(.leftArrow, modifiers: held) == nil)
            #expect(SheetCanvasInput.key("f", modifiers: held) == nil)
        }
    }

    @Test func aTypedDraftIsCommittedByTheModelOnce() {
        let (h, _) = harness()
        var submitted: [String] = []
        let owner = UUID()
        h.model.notePendingDraft(owner: owner) { submitted.append("first") }
        h.model.commitPendingEntry()
        h.model.commitPendingEntry()
        #expect(submitted == ["first"])
        h.model.notePendingDraft(owner: owner) { submitted.append("dropped") }
        h.model.discardPendingDraft(ownedBy: owner)
        h.model.commitPendingEntry()
        #expect(submitted == ["first"])
        h.model.notePendingDraft(owner: UUID()) { submitted.append("a") }
        h.model.notePendingDraft(owner: UUID()) { submitted.append("b") }
        h.model.commitPendingEntry()
        #expect(submitted == ["first", "a", "b"], "a second field commits the first's draft before taking its place")
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
        let control = ScaleControl(model: harness().0.model, current: nil, allowsSheetScale: true, standard: .iso) { _ in }
        #expect(custom == control.options.count - 1)
        #expect(ScaleControl.selectedIndex(current: nil, isCustom: false, allowsSheetScale: true) == 0)
    }

    @Test func customChosenOnOneViewDoesNotCarryToTheNext() async throws {
        let views = [EditorDocuments.view(at: Vector2(100, 100)), EditorDocuments.view(at: Vector2(200, 100))]
        let sheet = DrawingSheet(name: "Sheet 1", views: views)
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.selection = [views[0].id]
        let window = try await DrawingWindow.open(size: Size(width: Pixels(400), height: Pixels(600)), scaleFactor: 1) {
            DrawingInspector(model: h.model)
        }
        func fields() throws -> Int { try window.window.elements(role: .textField).count }
        let before = try fields()
        let menus = try window.window.elements(role: .popUpButton)
        let scaleMenu = try #require(menus.first { $0.value == "Sheet's" })
        window.window.click(at: Point(x: scaleMenu.frame.origin.x + 4, y: scaleMenu.frame.origin.y + 4))
        try await window.window.runUntilIdle()
        try window.window.chooseMenuItem("Custom…")
        try await window.window.runUntilIdle()
        #expect(try fields() == before + 2, "Custom… shows the two fields")
        h.model.selection = [views[1].id]
        try await window.window.runUntilIdle()
        #expect(try fields() == before, "the other view follows the sheet's scale")
    }

    @Test func aTypedScaleOnAViewIsOneStep() {
        let (h, view) = harness()
        h.model.setScale(DrawingScale(numerator: 1, denominator: 3), of: view.id)
        #expect(h.model.document.sheets[0].views[0].scale == DrawingScale(numerator: 1, denominator: 3))
        #expect(ScaleControl.selectedIndex(current: DrawingScale(numerator: 1, denominator: 3), isCustom: false, allowsSheetScale: true)
            == ScaleControl(model: harness().0.model, current: nil, allowsSheetScale: true, standard: .iso) { _ in }.options.count - 1)
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

/// The annotation pages and the sheet page's DR-2 rows (plan R20).
@MainActor
@Suite("Drawing inspector annotations")
struct DrawingInspectorAnnotationTests {
    private func open(_ scene: SelectionScene, height: Float = 1400) async throws -> DrawingWindow {
        try await DrawingWindow.open(size: Size(width: Pixels(400), height: Pixels(height)), scaleFactor: 1) {
            DrawingInspector(model: scene.h.model)
        }
    }

    private func texts(_ window: DrawingWindow) throws -> [String] {
        try window.window.elements(role: .staticText).compactMap { $0.value ?? $0.label }
    }

    @Test func aDimensionPageShowsItsRows() async throws {
        let scene = SelectionScene.make([.horizontal])
        scene.h.model.selectedAnnotations = [SelectionScene.horizontal]
        let shown = try texts(try await open(scene))
        for row in ["Kind", "Value", "Precision", "Tolerance", "General", "Prefix", "Suffix"] {
            #expect(shown.contains(row), "\(row) in \(shown)")
        }
        #expect(shown.contains { $0.hasPrefix("±") && $0.hasSuffix("(ISO 2768-m)") }, "the general tolerance's value: \(shown)")
    }

    @Test func aLostDimensionSaysWhyAndHowToReattach() async throws {
        let scene = SelectionScene.make([.horizontal], removing: [100])
        scene.h.model.selectedAnnotations = [SelectionScene.horizontal]
        let shown = try texts(try await open(scene))
        #expect(shown.contains(LostReason.missing.sentence), "\(shown)")
        #expect(shown.contains("Click a line to attach it again."))
        #expect(shown.contains { $0.hasSuffix("?") }, "the value reads with a question mark: \(shown)")
    }

    @Test func fitControlsAppearForFits() async throws {
        let scene = SelectionScene.make([.diameter])
        scene.h.model.selectedAnnotations = [SelectionScene.diameter]
        let plain = try texts(try await open(scene))
        #expect(!plain.contains("Letter") && !plain.contains("Grade"))
        scene.h.model.setTolerance(.fit(.hole(.H, grade: 7), showsDeviations: true), of: SelectionScene.diameter)
        let window = try await open(scene)
        let shown = try texts(window)
        #expect(shown.contains("Letter") && shown.contains("Grade"), "\(shown)")
        _ = try window.window.element(label: "Show deviations")
    }

    @Test func aNotePageEditsText() async throws {
        let scene = SelectionScene.make([.note])
        scene.h.model.selectedAnnotations = [SelectionScene.note]
        let window = try await open(scene)
        _ = try window.window.elements(where: { $0.value == "Plate" })[0]
        let add = try window.window.element(label: "Add Leader")
        window.window.click(at: Point(x: add.frame.origin.x + 4, y: add.frame.origin.y + 4))
        #expect(scene.h.model.addingLeader == SelectionScene.note)
        scene.h.model.setNoteText("Plate 2", of: SelectionScene.note)
        #expect(scene.note(SelectionScene.note)?.text == "Plate 2")
    }

    @Test func severalAnnotationsOfferDeleteAndACentreMarkOnlyDelete() async throws {
        let scene = SelectionScene.make([.horizontal, .mark])
        scene.h.model.selectedAnnotations = [SelectionScene.mark]
        let one = try texts(try await open(scene))
        #expect(one.contains("Centre mark") && !one.contains("Kind"), "\(one)")
        scene.h.model.selectedAnnotations = [SelectionScene.mark, SelectionScene.horizontal]
        let window = try await open(scene)
        #expect(try texts(window).contains("2 items selected"))
        let delete = try window.window.element(label: "Delete")
        window.window.click(at: Point(x: delete.frame.origin.x + 4, y: delete.frame.origin.y + 4))
        #expect(scene.h.log.commits.map(\.name) == ["Delete Annotations"])
    }

    @Test func theSheetPageListsLostReferences() async throws {
        let scene = SelectionScene.make([.horizontal], removing: [100])
        let shown = try texts(try await open(scene))
        #expect(shown.contains("LOST REFERENCES"), "\(shown)")
        #expect(shown.contains { $0.hasSuffix(LostReason.missing.sentence) }, "\(shown)")
        let clean = SelectionScene.make([.horizontal])
        #expect(!(try texts(try await open(clean))).contains("LOST REFERENCES"))
    }

    @Test func decimalSignIsISOOnly() async throws {
        let scene = SelectionScene.make([])
        #expect(try texts(try await open(scene)).contains("Decimal sign"))
        scene.h.model.setStandard(.asme)
        #expect(!(try texts(try await open(scene)).contains("Decimal sign")))
    }

    @Test func asmeShowsTheDecimalsTable() async throws {
        let scene = SelectionScene.make([])
        scene.h.model.setStandard(.asme)
        let shown = try texts(try await open(scene))
        for row in ["0 decimals", "1 decimal", "2 decimals"] { #expect(shown.contains(row), "\(row) in \(shown)") }
        #expect(!shown.contains("Geometric"))
        let iso = SelectionScene.make([])
        let isoShown = try texts(try await open(iso))
        #expect(isoShown.contains("Geometric") && !isoShown.contains("0 decimals"))
    }

    @Test func aViewPageOffersCentreMarks() async throws {
        let scene = SelectionScene.make([])
        scene.h.model.selection = [scene.view.id]
        let window = try await open(scene)
        let toggle = try window.window.element(label: "Centre marks")
        window.window.click(at: Point(x: toggle.frame.origin.x + 4, y: toggle.frame.origin.y + 4))
        #expect(scene.h.model.document.sheets[0].views[0].showsCentreMarks == false)
    }
}

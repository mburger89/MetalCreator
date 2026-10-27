import CreatorGeometry
import CreatorKernel
import Foundation
import MetalUI
import Testing
@testable import CreatorViewport

/// The value box (spec §7): opened by a double-click on a dimension's text, it holds a draft that changes nothing until Return.
@MainActor
struct ValueBoxTests {
    let id = OverlayDimensionID("a")
    let measure = TextMeasure.eightPerCharacter

    func makeModel() -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: topDownPose(pointsPerMillimetre: 2), clock: ManualClock())
        model.viewSize = dimensionTestSize
        return model
    }

    func makeEditor(text: String = "60") -> FakeDimensionEditor {
        let editor = FakeDimensionEditor()
        editor.contents[id] = DimensionValueBoxContent(text: text, note: nil)
        return editor
    }

    /// Shows the 60 mm dimension, places it, and returns the middle of its text.
    func show(_ model: ViewportModel) throws -> ScreenPoint {
        model.showDimensions([sixtyMillimetres()])
        let placed = try #require(model.placedDimensions(measuring: measure).first)
        return ScreenPoint(placed.textOrigin.x + placed.textSize.width / 2, placed.textOrigin.y + placed.textSize.height / 2)
    }

    /// A model with the dimension shown and its box open on "60".
    func openBox(_ editor: FakeDimensionEditor, _ model: ViewportModel) throws -> ScreenPoint {
        model.dimensionEditor = editor
        let centre = try show(model)
        #expect(model.openValueBox(for: id))
        return centre
    }

    @Test func aDoubleClickOnTextOpensTheBoxWithItsValueSelected() throws {
        let model = makeModel()
        let editor = makeEditor()
        model.dimensionEditor = editor
        let centre = try show(model)
        model.click(at: centre, clickCount: 1)
        #expect(model.valueBox == nil)
        model.click(at: centre, clickCount: 2)
        let box = try #require(model.valueBox)
        #expect(box.id == id)
        #expect(box.draft == "60" && box.opening == "60")
        #expect(box.selection == TextSelection(range: "60".startIndex..<"60".endIndex))
        #expect(!box.isChecking && box.message == nil)
        #expect(editor.contentRequests == 1)
    }

    @Test func aSingleClickOnTextReachesNeitherToolNorPick() throws {
        let model = makeModel()
        let tool = RecordingTool()
        model.tool = tool
        var clicked = 0
        model.events.clicked = { _ in clicked += 1 }
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        let centre = try show(model)
        model.click(at: centre)
        #expect(!tool.calls.contains { $0.hasPrefix("clicked") } && tool.modelPicks.isEmpty)
        #expect(clicked == 0)
        model.click(at: ScreenPoint(5, 5))
        #expect(tool.calls.filter { $0.hasPrefix("clicked") } == ["clicked 5,5"], "a click off the text still reaches the tool")
    }

    @Test func aDimensionWithNoContentOpensNoBox() throws {
        let model = makeModel()
        let editor = FakeDimensionEditor()
        model.dimensionEditor = editor
        let centre = try show(model)
        model.click(at: centre, clickCount: 2)
        #expect(model.valueBox == nil)
        #expect(editor.contentRequests == 1)
        #expect(!model.openValueBox(for: id))
        let without = makeModel()
        _ = try show(without)
        #expect(!without.openValueBox(for: id), "no editor, no box")
    }

    @Test func typingChangesOnlyTheDraft() throws {
        let model = makeModel()
        let editor = makeEditor()
        _ = try openBox(editor, model)
        let (key, pose, dimensions) = (model.renderKey, model.pose, model.dimensions)
        model.valueBoxDraftChanged("7")
        #expect(model.valueBox?.draft == "7")
        model.valueBoxDraftChanged("70")
        #expect(model.valueBox?.draft == "70" && model.valueBox?.opening == "60")
        let selection = TextSelection(insertionPoint: "70".endIndex)
        model.valueBoxSelectionChanged(selection)
        #expect(model.valueBox?.selection == selection)
        #expect(editor.commits.isEmpty)
        #expect(model.renderKey == key && model.pose == pose && model.dimensions == dimensions)
    }

    @Test func returnCommitsTheTypedTextOnce() async throws {
        let model = makeModel()
        let editor = makeEditor()
        _ = try openBox(editor, model)
        let pose = model.pose
        model.valueBoxDraftChanged("70")
        await model.submitValueBox()
        #expect(editor.commits == [FakeDimensionEditor.Commit(text: "70", id: id)])
        #expect(model.valueBox == nil)
        #expect(model.pose == pose)
        await model.submitValueBox()
        #expect(editor.commits.count == 1, "no box, no second commit")
    }

    @Test func returnWithTheOpeningTextCommitsNothing() async throws {
        let model = makeModel()
        let editor = makeEditor(text: "12.5")
        _ = try openBox(editor, model)
        await model.submitValueBox()
        #expect(editor.commits.isEmpty)
        #expect(model.valueBox == nil)
        _ = try openBox(editor, model)
        model.valueBoxDraftChanged("12.50")
        model.valueBoxDraftChanged("12.5")
        await model.submitValueBox()
        #expect(editor.commits.isEmpty, "typed back to the opening text is untouched")
    }

    @Test func aRefusalKeepsTheBoxOpenWithTheMessage() async throws {
        let model = makeModel()
        let editor = makeEditor()
        editor.outcome = .refused("A length must be more than 0 mm.")
        _ = try openBox(editor, model)
        model.valueBoxDraftChanged("0")
        await model.submitValueBox()
        let box = try #require(model.valueBox)
        #expect(box.message == "A length must be more than 0 mm.")
        #expect(box.draft == "0" && box.opening == "60" && !box.isChecking)
        editor.outcome = .accepted
        model.valueBoxDraftChanged("5")
        await model.submitValueBox()
        #expect(model.valueBox == nil)
        #expect(editor.commits.map(\.text) == ["0", "5"])
    }

    @Test func whileCheckingTheBoxTakesNoInput() async throws {
        let model = makeModel()
        let editor = makeEditor()
        editor.holdsCommits = true
        _ = try openBox(editor, model)
        model.valueBoxDraftChanged("70")
        let first = Task { await model.submitValueBox() }
        await editor.waitUntilHeld()
        #expect(model.valueBox?.isChecking == true)
        model.valueBoxDraftChanged("80")
        model.valueBoxSelectionChanged(TextSelection(insertionPoint: "70".startIndex))
        await model.submitValueBox()
        model.cancelValueBox()
        #expect(model.valueBox?.draft == "70" && model.valueBox?.selection != TextSelection(insertionPoint: "70".startIndex))
        #expect(editor.commits.count == 1)
        #expect(!model.openValueBox(for: id), "a box is being checked")
        editor.release()
        await first.value
        #expect(model.valueBox == nil)
    }

    @Test func losingFocusWhileCheckingKeepsTheBox() async throws {
        let model = makeModel()
        let editor = makeEditor()
        editor.holdsCommits = true
        editor.outcome = .refused("No.")
        _ = try openBox(editor, model)
        model.valueBoxDraftChanged("70")
        let first = Task { await model.submitValueBox() }
        await editor.waitUntilHeld()
        model.valueBoxLostFocus()
        #expect(model.valueBox?.isChecking == true)
        editor.release()
        await first.value
        #expect(model.valueBox?.message == "No.")
        model.valueBoxLostFocus()
        #expect(model.valueBox == nil, "idle, losing focus cancels")
        #expect(editor.commits.count == 1)
    }

    @Test func escapeOrAClickElsewhereCancels() throws {
        let model = makeModel()
        let editor = makeEditor()
        _ = try openBox(editor, model)
        model.valueBoxDraftChanged("70")
        model.cancelValueBox()
        #expect(model.valueBox == nil)
        _ = try openBox(editor, model)
        model.click(at: ScreenPoint(5, 5))
        #expect(model.valueBox == nil)
        #expect(editor.commits.isEmpty)
    }

    @Test func theBoxClosesWhenItsDimensionGoesAway() throws {
        let model = makeModel()
        let editor = makeEditor()
        _ = try openBox(editor, model)
        model.showDimensions([sixtyMillimetres(id: "other")])
        #expect(model.valueBox == nil)
        _ = try openBox(editor, model)
        model.showDimensions([])
        #expect(model.valueBox == nil)
        #expect(editor.commits.isEmpty)
    }

    @Test func aBoxHeldOpenByACommitClosesWhenItsDimensionGoesAway() async throws {
        let model = makeModel()
        let editor = makeEditor()
        editor.holdsCommits = true
        editor.outcome = .refused("Late.")
        _ = try openBox(editor, model)
        model.valueBoxDraftChanged("70")
        let first = Task { await model.submitValueBox() }
        await editor.waitUntilHeld()
        model.showDimensions([])
        #expect(model.valueBox == nil)
        editor.release()
        await first.value
        #expect(model.valueBox == nil, "a late answer reopens nothing")
    }

    @Test func theBoxSitsOverTheTextAndHidesIt() throws {
        let model = makeModel()
        let editor = makeEditor()
        let centre = try openBox(editor, model)
        let placed = try #require(model.placedDimensions(measuring: measure).first)
        #expect(!placed.showsText && !placed.textContains(centre), "the edited dimension's own text is not drawn")
        let box = try #require(model.placedValueBox(measuring: measure))
        #expect(box.size == ViewportSize(width: 72, height: 22))
        #expect(abs(box.origin.x + box.size.width / 2 - centre.x) < 1e-9)
        #expect(abs(box.origin.y + box.size.height / 2 - centre.y) < 1e-9)
        model.valueBoxDraftChanged("1234567890")
        #expect(model.placedValueBox(measuring: measure)?.size == ViewportSize(width: 96, height: 22), "80 wide draft + 16")
        model.valueBoxDraftChanged("12345")
        #expect(model.placedValueBox(measuring: TextMeasure { _ in ViewportSize(width: 50.2, height: 12) })?.size.width == 72)
        #expect(model.placedValueBox(measuring: TextMeasure { _ in ViewportSize(width: 60.2, height: 12) })?.size.width == 77)
        // Off screen for a moment (the camera moves), the box stays where it was last drawn.
        let before = model.placedValueBox(measuring: measure)?.origin
        model.perform(.view(.front))
        #expect(model.isAnimating && model.placedDimensions(measuring: measure).isEmpty)
        #expect(model.placedValueBox(measuring: measure)?.origin == before)
        model.cancelValueBox()
        #expect(model.placedValueBox(measuring: measure) == nil)
    }
}

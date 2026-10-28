import CreatorGeometry
import CreatorKernel
import Foundation
import MetalUI
import Testing
@testable import CreatorViewport

/// Every way a value box ends is reported to the editor once, so a new dimension can be kept or dropped (spec §4.2).
@MainActor
struct ValueBoxEndingTests {
    let id = OverlayDimensionID("a")
    let measure = TextMeasure.eightPerCharacter

    /// A model with the 60 mm dimension shown and its box open on "60", and the editor it reports to.
    func openBox() throws -> (ViewportModel, FakeDimensionEditor, ScreenPoint) {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: topDownPose(pointsPerMillimetre: 2), clock: ManualClock())
        model.viewSize = dimensionTestSize
        let editor = FakeDimensionEditor()
        editor.contents[id] = DimensionValueBoxContent(text: "60", note: nil)
        model.dimensionEditor = editor
        model.showDimensions([sixtyMillimetres()])
        let placed = try #require(model.placedDimensions(measuring: measure).first)
        let centre = ScreenPoint(placed.textOrigin.x + placed.textSize.width / 2, placed.textOrigin.y + placed.textSize.height / 2)
        #expect(model.openValueBox(for: id))
        return (model, editor, centre)
    }

    @Test func anAcceptedCommitEndsCommitted() async throws {
        let (model, editor, _) = try openBox()
        model.valueBoxDraftChanged("70")
        await model.submitValueBox()
        #expect(editor.endings == [.init(id: id, ending: .committed)])
        #expect(editor.commits.count == 1)
    }

    @Test func anUntouchedReturnEndsUnchanged() async throws {
        let (model, editor, _) = try openBox()
        await model.submitValueBox()
        #expect(editor.endings == [.init(id: id, ending: .unchanged)])
        #expect(editor.commits.isEmpty)
    }

    @Test func escapeFocusLossAndAClickElsewhereEndCancelled() throws {
        var (model, editor, _) = try openBox()
        model.cancelValueBox()
        #expect(editor.endings == [.init(id: id, ending: .cancelled)])
        model.cancelValueBox()
        #expect(editor.endings.count == 1, "no box, no second ending")

        (model, editor, _) = try openBox()
        model.valueBoxLostFocus()
        #expect(editor.endings == [.init(id: id, ending: .cancelled)])

        (model, editor, _) = try openBox()
        model.click(at: ScreenPoint(2, 2))
        #expect(editor.endings == [.init(id: id, ending: .cancelled)])
        #expect(model.valueBox == nil)
    }

    @Test func aRefusalDoesNotEnd() async throws {
        let (model, editor, _) = try openBox()
        editor.outcome = .refused("No.")
        model.valueBoxDraftChanged("70")
        await model.submitValueBox()
        #expect(editor.endings.isEmpty)
        #expect(model.valueBox?.message == "No.")
    }

    @Test func aDimensionThatGoesAwayEndsCancelled() throws {
        let (model, editor, _) = try openBox()
        model.showDimensions([])
        #expect(editor.endings == [.init(id: id, ending: .cancelled)])
        #expect(model.valueBox == nil)
    }
}

import CreatorGeometry
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The sheet inspector's notes, edge break and general surface requirement (DR-4 R12, R15).
@MainActor
@Suite("Sheet notes model")
struct SheetNotesModelTests {
    private static let breakSentence = "An edge break is one or two lengths greater than 0, the smaller first."

    private func scene() -> SelectionScene { SelectionScene.make([]) }
    private func notes(_ s: SelectionScene) -> SheetNotes { s.h.model.document.sheets[0].notes }
    private func names(_ s: SelectionScene) -> [String] { s.h.log.commits.map(\.name) }

    @Test func notesSplitIntoLines() {
        let s = scene()
        s.h.model.setGeneralNotes("Material: 6061  \n\n  Paint after machining\t\n")
        #expect(notes(s).lines == ["Material: 6061", "  Paint after machining"])
        #expect(names(s) == ["Edit Notes"])
        s.h.model.setGeneralNotes("Material: 6061\n  Paint after machining")
        #expect(names(s).count == 1, "no change, no step")
        s.h.model.setGeneralNotes("")
        #expect(notes(s).lines.isEmpty)
        #expect(names(s).count == 2)
    }

    @Test func anEdgeBreakNeedsOrderedLengths() {
        let s = scene()
        s.h.model.setEdgeBreak(minimumText: "0.5", maximumText: "0.2")
        #expect(s.h.model.refusal == Self.breakSentence)
        #expect(notes(s).edgeBreak == nil)
        #expect(names(s).isEmpty)
        s.h.model.setEdgeBreak(minimumText: "0", maximumText: "0.2")
        #expect(s.h.model.refusal == Self.breakSentence)
        s.h.model.setEdgeBreak(minimumText: "x", maximumText: "")
        #expect(s.h.model.refusal == Self.breakSentence)
        s.h.model.setEdgeBreak(minimumText: "0.3", maximumText: "")
        #expect(notes(s).edgeBreak == EdgeBreak(minimum: 0.3, maximum: 0.3))
        #expect(names(s) == ["Change Edge Break"])
        s.h.model.setEdgeBreak(minimumText: "", maximumText: "0.3")
        #expect(names(s).count == 1)
        s.h.model.setEdgeBreak(minimumText: "0.2", maximumText: "0.5")
        #expect(notes(s).edgeBreak == EdgeBreak(minimum: 0.2, maximum: 0.5))
        s.h.model.setEdgeBreak(minimumText: "", maximumText: "")
        #expect(notes(s).edgeBreak == nil)
    }

    @Test func anEdgeBreakTakesTheCommaItIsShownWith() {
        let s = scene()
        s.h.model.setEdgeBreak(minimumText: "0,5", maximumText: "1,5")
        #expect(notes(s).edgeBreak == EdgeBreak(minimum: 0.5, maximum: 1.5))
        s.h.model.setEdgeBreak(minimumText: "0.3", maximumText: "1,5")
        #expect(notes(s).edgeBreak == EdgeBreak(minimum: 0.3, maximum: 1.5))
    }

    @Test func theGeneralSurfaceIsSet() {
        let s = scene()
        s.h.model.setGeneralSurface(SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 3.2))
        #expect(names(s) == ["Change General Surface"])
        #expect(notes(s).surface?.value == 3.2)
        s.h.model.setGeneralSurface(SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 3.2))
        #expect(names(s).count == 1)
        s.h.model.setGeneralSurfaceValue(text: "1.6")
        #expect(notes(s).surface?.value == 1.6)
        #expect(names(s) == ["Change General Surface", "Change General Surface"])
        s.h.model.setGeneralSurfaceValue(text: "-1")
        #expect(s.h.model.refusal == "A roughness value is a number greater than 0, such as 1.6.")
        s.h.model.setGeneralSurface(nil)
        #expect(notes(s).surface == nil)
    }
}

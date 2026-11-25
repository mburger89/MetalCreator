import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Selecting, moving, nudging and deleting annotations, and what a cancelled drag leaves.
@MainActor
@Suite("Annotation selection")
struct AnnotationSelectionTests {
    private typealias Scene = SelectionScene

    @Test func annotationsAreHitBeforeViews() {
        let s = Scene.make([.horizontal])
        s.h.click(s.centre(of: Scene.horizontal).x, s.centre(of: Scene.horizontal).y)
        #expect(s.h.model.selectedAnnotations == [Scene.horizontal])
        #expect(s.h.model.selection.isEmpty)
        s.h.click(s.mapping.sheet(Vector2(2, 2)).x, s.mapping.sheet(Vector2(2, 2)).y)
        #expect(s.h.model.selection == [s.view.id], "inside the view and off every annotation, the view")
        #expect(s.h.model.selectedAnnotations.isEmpty)
        #expect(s.h.log.commits.isEmpty)
    }

    @Test func shiftAddsAnnotations() {
        let s = Scene.make([.horizontal, .note])
        let a = s.centre(of: Scene.horizontal), b = s.centre(of: Scene.note)
        s.h.click(a.x, a.y)
        s.h.click(b.x, b.y, .shift)
        #expect(s.h.model.selectedAnnotations == [Scene.horizontal, Scene.note])
        s.h.click(20, 20)
        #expect(s.h.model.selectedAnnotations.isEmpty)
        s.h.click(a.x, a.y)
        s.h.click(b.x, b.y)
        #expect(s.h.model.selectedAnnotations == [Scene.note], "a plain click on another annotation replaces the selection")
    }

    @Test func aDragMovesTheDimensionLine() throws {
        let s = Scene.make([.horizontal])
        let from = s.centre(of: Scene.horizontal) - Vector2(7, 0)
        let label = s.label(of: Scene.horizontal)
        #expect(abs(from.x - label.x) > 3, "the press is off the text")
        s.drag(from: from, by: Vector2(0, -5))
        #expect(s.h.log.commits.count == 2)
        #expect(Set(s.h.log.commits.map(\.name)) == ["Move Dimension"])
        #expect(Set(s.h.log.commits.map(\.coalescingKey)).count == 1)
        let moved = try #require(s.dimension(Scene.horizontal))
        #expect(abs(moved.placement.offset - 5) < 1e-9, "10 + (-5) along n")
        #expect(moved.placement.textShift == nil)
    }

    @Test func draggingTheTextShiftsIt() throws {
        let s = Scene.make([.horizontal])
        s.drag(from: s.label(of: Scene.horizontal), by: Vector2(3, 2))
        let moved = try #require(s.dimension(Scene.horizontal))
        #expect(abs(moved.placement.offset - 12) < 1e-9)
        let shift = try #require(moved.placement.textShift)
        #expect(abs(shift - 3) < 1e-6, "the automatic shift is 0 for centred text")
    }

    @Test func aRadialDragTurnsTheLeader() throws {
        let s = Scene.make([.diameter])
        let before = try #require(s.dimension(Scene.diameter)).placement
        s.drag(from: s.label(of: Scene.diameter), by: Vector2(-6, 6))
        let after = try #require(s.dimension(Scene.diameter)).placement
        #expect(abs(after.angle - before.angle) > 0.1, "\(before) \(after)")
        #expect(s.h.log.commits.allSatisfy { $0.name == "Move Dimension" })
    }

    @Test func aNoteDragMovesItsPosition() throws {
        let s = Scene.make([.note])
        s.drag(from: s.centre(of: Scene.note), by: Vector2(10, 5))
        #expect(s.note(Scene.note)?.position == Vector2(70, -5))
        #expect(Set(s.h.log.commits.map(\.name)) == ["Move Note"])
    }

    @Test func mixedIsMoveAnnotations() {
        let s = Scene.make([.horizontal, .note])
        s.h.model.selectedAnnotations = [Scene.horizontal, Scene.note]
        s.drag(from: s.centre(of: Scene.note), by: Vector2(4, 0))
        #expect(Set(s.h.log.commits.map(\.name)) == ["Move Annotations"])
        #expect(s.note(Scene.note)?.position == Vector2(64, -10))
        #expect(s.dimension(Scene.horizontal)?.placement.offset == 10, "a horizontal drag leaves the offset along n")
    }

    @Test func nudgeMovesSelectedAnnotations() {
        let s = Scene.make([.note])
        s.h.model.selectedAnnotations = [Scene.note]
        #expect(s.h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: false)))
        #expect(s.h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: true)))
        #expect(s.note(Scene.note)?.position == Vector2(62, -10))
        #expect(Set(s.h.log.commits.map(\.name)) == ["Move Note"])
        #expect(Set(s.h.log.commits.map(\.coalescingKey)).count == 1)
    }

    @Test func deleteNames() {
        func deleted(_ pieces: [Scene.Piece], _ ids: [AnnotationID], views: Bool = false) -> (String?, Int) {
            let s = Scene.make(pieces)
            s.h.model.selectedAnnotations = Set(ids)
            if views { s.h.model.selection = [s.view.id] }
            #expect(s.h.model.keyPressed(.delete))
            return (s.h.log.commits.last?.name, s.h.model.document.sheets[0].annotations.count)
        }
        #expect(deleted([.horizontal, .diameter], [Scene.horizontal, Scene.diameter]) == ("Delete Dimension", 0))
        #expect(deleted([.note], [Scene.note]) == ("Delete Note", 0))
        #expect(deleted([.note, .horizontal], [Scene.note, Scene.horizontal]) == ("Delete Annotations", 0))
        #expect(deleted([.mark], [Scene.mark]) == ("Delete Annotations", 0))
        #expect(deleted([.note], [Scene.note], views: true) == ("Delete View", 0))
    }

    @Test func deletingAViewDeletesItsAnnotations() {
        let s = Scene.make([.horizontal, .note, .mark])
        s.h.model.selection = [s.view.id]
        s.h.model.deleteSelection()
        #expect(s.h.log.commits.map(\.name) == ["Delete View"])
        #expect(s.h.model.document.sheets[0].annotations.isEmpty)
        #expect(s.h.model.document.sheets[0].views.isEmpty)
    }

    @Test func duplicateSheetCopiesAnnotations() throws {
        let s = Scene.make([.horizontal, .note])
        let original = s.h.model.document.sheets[0]
        s.h.model.duplicateSheet(original.id)
        let copy = try #require(s.h.model.document.sheets.last)
        #expect(copy.id != original.id)
        #expect(copy.annotations.count == 2)
        #expect(Set(copy.annotations.map(\.id)).isDisjoint(with: Set(original.annotations.map(\.id))))
        let copiedView = try #require(copy.views.first?.id)
        #expect(copiedView != original.views[0].id)
        #expect(copy.annotations.allSatisfy { $0.view == copiedView })
        #expect(s.h.model.document.sheets[0] == original, "the original is untouched")
        #expect(copy.annotations.compactMap { annotation -> DrawingDimension? in
            if case .dimension(let dimension) = annotation.kind { dimension } else { nil }
        }.first?.anchors == s.dimension(Scene.horizontal)?.anchors)
    }

    @Test func aCancelledDragRestoresAndDiscards() throws {
        let s = Scene.make([.note])
        let base = s.h.model.document
        s.press(s.centre(of: Scene.note))
        s.drag(to: s.centre(of: Scene.note) + Vector2(5, 5))
        #expect(s.h.model.document != base)
        let key = try #require(s.h.log.commits.last?.coalescingKey)
        s.h.model.pointerCancelled()
        #expect(s.h.model.document == base)
        #expect(s.h.log.discarded == [key])
        s.h.model.pointerCancelled()
        #expect(s.h.log.discarded == [key], "once")
    }

    @Test func aCancelledViewDragRestoresToo() throws {
        let s = Scene.make([])
        let base = s.h.model.document
        s.press(s.mapping.sheet(Vector2(2, 2)))
        s.drag(to: s.mapping.sheet(Vector2(2, 2)) + Vector2(5, 5))
        s.h.model.pointerCancelled()
        #expect(s.h.model.document == base)
        #expect(s.h.log.discarded.count == 1)
    }

    @Test func aCancelledPressThatChangedNothingDiscardsNothing() {
        let s = Scene.make([.note])
        s.press(s.centre(of: Scene.note))
        s.h.model.pointerCancelled()
        #expect(s.h.log.discarded.isEmpty)
    }

    @Test func documentForSavingWritesRemembered() throws {
        let s = Scene.make([.horizontal, .note])
        let remembered = try #require(s.h.model.remembered[Scene.horizontal])
        let saved = s.h.model.documentForSaving()
        #expect(saved.sheets[0].annotation(Scene.horizontal)?.last == remembered)
        #expect(s.h.model.document.sheets[0].annotation(Scene.horizontal)?.last == nil, "the editor's own document is not changed")
        #expect(s.h.log.commits.isEmpty)
        let noteLast = s.h.model.remembered[Scene.note]
        #expect(saved.sheets[0].annotation(Scene.note)?.last == noteLast)
    }

    @Test func undoPrunesTheAnnotationSelectionAndPicks() throws {
        let s = Scene.make([.horizontal, .note])
        let model = s.h.model
        let full = model.document
        var bare = full
        bare.sheets[0].removeView(s.view.id)
        #expect(bare.sheets[0].annotations.isEmpty)

        model.selectedAnnotations = [Scene.horizontal]
        model.press(.dimension)
        let edge = s.mapping.sheet(Vector2(20, 5))
        s.h.click(edge.x, edge.y)
        #expect(model.picks.count == 1, "\(model.refusal ?? "")")
        #expect(model.pickView == s.view.id)
        model.replaceDocument(full)
        #expect(model.selectedAnnotations == [Scene.horizontal], "a replace that keeps them keeps them")
        #expect(model.picks.count == 1)
        model.replaceDocument(bare)
        #expect(model.selectedAnnotations.isEmpty)
        #expect(model.picks.isEmpty)
        #expect(model.draftPicture == nil)
        #expect(model.pickView == nil)
        #expect(model.hoverCandidate == nil)

        model.replaceDocument(full)
        model.beginLeader(for: Scene.note)
        #expect(model.addingLeader == Scene.note)
        model.replaceDocument(full)
        #expect(model.addingLeader == Scene.note)
        model.replaceDocument(bare)
        #expect(model.addingLeader == nil)
    }
}

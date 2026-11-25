import CreatorGeometry
import CreatorKernel
import MetalUI
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Notes and their leaders, units and the last good figures of annotations.
@MainActor
@Suite("Annotation notes")
struct AnnotationNoteTests {
    typealias Fixtures = AnnotationEditorFixtures
    private typealias Opened = OpenedView

    private func open(
        _ content: ViewContent, orientation: StandardOrientation, zoom: Double = 1,
        annotations: (ViewID) -> [DrawingAnnotation] = { _ in [] }, units: DocumentUnits = .millimetres
    ) -> Opened {
        Opened.make(content, orientation: orientation, zoom: zoom, annotations: annotations, units: units)
    }

    private func at(_ o: Opened, _ x: Double, _ y: Double) -> Vector2 { o.at(x, y) }

    private func click(_ o: Opened, _ point: Vector2, _ modifiers: SheetModifiers = []) { o.click(point, modifiers) }

    private func note(_ h: EditorHarness) throws -> (annotation: DrawingAnnotation, note: DrawingNote) {
        let annotation = try #require(h.model.document.sheets[0].annotations.first)
        guard case .note(let note) = annotation.kind else {
            Issue.record("not a note: \(annotation.kind)")
            throw CancellationError()
        }
        return (annotation, note)
    }

    // MARK: Notes and leaders

    @Test func aNoteInAViewBelongsToIt() async throws {
        let o = open(try await Fixtures.plate(.front), orientation: .front)
        o.h.model.press(.note)
        let point = Fixtures.centre + Vector2(5, 2)
        click(o, point)
        #expect(o.h.log.commits.map(\.name) == ["Add Note"])
        let (annotation, made) = try note(o.h)
        #expect(annotation.view == o.view.id)
        #expect(made.position == Vector2(5, 2), "relative to the view's centre")
        #expect(made.text == "Note")
        #expect(o.h.model.selectedAnnotations == [annotation.id])
    }

    @Test func aNoteOutsideIsFree() async throws {
        let o = open(try await Fixtures.plate(.front), orientation: .front)
        o.h.model.press(.note)
        click(o, Vector2(50, 50))
        let (annotation, made) = try note(o.h)
        #expect(annotation.view == nil)
        #expect(made.position == Vector2(50, 50))
    }

    private func openWithNote(
        view: ViewID? = nil, at position: Vector2, free: Bool = false
    ) async throws -> (Opened, AnnotationID) {
        let content = try await Fixtures.plate(.front)
        var id = AnnotationID()
        let o = open(content, orientation: .front) { viewID in
            let annotation = DrawingAnnotation(
                view: free ? nil : viewID, kind: .note(DrawingNote(text: "Hello", position: position)))
            id = annotation.id
            return [annotation]
        }
        return (o, id)
    }

    @Test func aLeaderEndsOnTheNextClick() async throws {
        let (o, id) = try await openWithNote(at: Vector2(-10, 20))
        let bounds = try #require(o.content.projection?.bounds)
        o.h.model.beginLeader(for: id)
        #expect(o.h.model.addingLeader == id)
        click(o, at(o, bounds.center.x, bounds.min.y))
        #expect(o.h.log.commits.map(\.name) == ["Add Leader"])
        let (_, made) = try note(o.h)
        #expect(made.leaders.count == 1)
        guard case .edge = made.leaders[0].target else {
            Issue.record("expected an edge: \(made.leaders)")
            return
        }
        #expect(o.h.model.addingLeader == nil)
    }

    @Test func aLeaderIntoAnotherViewIsRefused() async throws {
        let front = try await Fixtures.plate(.front)
        let top = try await Fixtures.plate(.top)
        let first = EditorDocuments.view(at: Fixtures.centre, orientation: .front)
        let second = EditorDocuments.view(at: Vector2(300, 150), orientation: .top)
        let annotation = DrawingAnnotation(
            view: first.id, kind: .note(DrawingNote(text: "Hello", position: Vector2(-10, 20))))
        let sheet = DrawingSheet(name: "Sheet 1", views: [first, second], annotations: [annotation])
        let h = EditorHarness(
            document: EditorDocuments.document([sheet]), sheet: sheet.id, contents: [first.id: front, second.id: top])
        h.model.beginLeader(for: annotation.id)
        let bounds = try #require(top.projection?.bounds)
        let mapping = try #require(ViewMapping.of(projection: top.projection!, center: Vector2(300, 150), scale: 1))
        let onTop = mapping.sheet(Vector2(bounds.center.x, bounds.min.y))
        h.click(onTop.x, onTop.y)
        #expect(h.model.refusal == "A note's leaders point into one view.")
        #expect(h.log.commits.isEmpty)
    }

    @Test func aSheetNotesFirstLeaderJoinsThatView() async throws {
        let (o, id) = try await openWithNote(at: Vector2(300, 200), free: true)
        let bounds = try #require(o.content.projection?.bounds)
        let before = try #require(o.h.model.picture).texts.filter { $0.annotation == id }.map(\.origin)
        #expect(!before.isEmpty)
        o.h.model.beginLeader(for: id)
        click(o, at(o, bounds.center.x, bounds.min.y))
        #expect(o.h.log.commits.map(\.name) == ["Add Leader"])
        let (annotation, made) = try note(o.h)
        #expect(annotation.view == o.view.id)
        #expect(made.position == Vector2(150, 50), "relative to the view's centre")
        #expect(made.leaders.count == 1)
        let after = try #require(o.h.model.picture).texts.filter { $0.annotation == id }.map(\.origin)
        #expect(after == before, "the note is drawn where it was")
    }

    @Test func aJoinedNoteMovesWithItsView() async throws {
        let (o, id) = try await openWithNote(at: Vector2(300, 200), free: true)
        let bounds = try #require(o.content.projection?.bounds)
        o.h.model.beginLeader(for: id)
        click(o, at(o, bounds.center.x, bounds.min.y))
        let before = try #require(o.h.model.picture).texts.filter { $0.annotation == id }.map(\.origin)
        o.h.model.selection = [o.view.id]
        #expect(o.h.model.keyPressed(.nudge(Vector2(10, 0), isRepeat: false)))
        let after = try #require(o.h.model.picture).texts.filter { $0.annotation == id }.map(\.origin)
        #expect(after.count == before.count)
        for (a, b) in zip(after, before) { #expect(abs(a.x - b.x - 10) < 1e-9 && abs(a.y - b.y) < 1e-9) }
    }

    @Test func aSheetNotesPointLeaderLeavesItFree() async throws {
        let (o, id) = try await openWithNote(at: Vector2(300, 200), free: true)
        o.h.model.beginLeader(for: id)
        click(o, Vector2(100, 100))
        #expect(o.h.log.commits.map(\.name) == ["Add Leader"])
        let (annotation, made) = try note(o.h)
        #expect(annotation.view == nil)
        #expect(made.leaders.map(\.target) == [.point(Vector2(100, 100))])
        #expect(made.position == Vector2(300, 200))
    }

    // MARK: Units and the last good figures

    private func widthDimension(_ topology: Topology) -> (ViewID) -> [DrawingAnnotation] {
        { view in
            [
                DrawingAnnotation(
                    view: view,
                    kind: .dimension(
                        DrawingDimension(
                            kind: .linear(.horizontal), anchors: [Fixtures.pick(topology, 102)],
                            placement: DimensionPlacement(offset: 10, angle: 0)))),
            ]
        }
    }

    @Test func unitsChangeRebuildsThePicture() throws {
        let topology = Fixtures.topology()
        let o = open(Fixtures.top(topology), orientation: .top, annotations: widthDimension(topology))
        let id = try #require(o.h.model.document.sheets[0].annotations.first?.id)
        let before = try #require(o.h.model.picture).texts.filter { $0.annotation == id }.map(\.original)
        #expect(before.contains("40"), "\(before)")
        o.h.model.units = DocumentUnits(length: .inches)
        let after = try #require(o.h.model.picture).texts.filter { $0.annotation == id }.map(\.original)
        #expect(after != before)
        #expect(after.contains { $0.hasPrefix("1.57") }, "\(after)")
    }

    @Test func rememberedKeepsTheNewestHeld() throws {
        let topology = Fixtures.topology()
        let o = open(Fixtures.top(topology), orientation: .top, annotations: widthDimension(topology))
        let id = try #require(o.h.model.document.sheets[0].annotations.first?.id)
        #expect(try #require(o.h.model.remembered[id]).values.first.map { abs($0 - 40) < 1e-9 } == true)
        // The edge goes: the dimension is lost and keeps showing 40, with a question mark.
        o.h.model.contents[o.view.id] = Fixtures.top(Fixtures.topology(removing: [102]))
        #expect(o.h.model.picture?.annotationReports[id]?.isLost == true)
        #expect(o.h.model.remembered[id]?.values.first.map { abs($0 - 40) < 1e-9 } == true)
        let lost = try #require(o.h.model.picture).texts.filter { $0.annotation == id }.map(\.original)
        #expect(lost.contains("40?"), "\(lost)")
        // It grows, and the newest held value replaces it.
        let grown = Fixtures.topology(width: 60)
        o.h.model.contents[o.view.id] = Fixtures.top(grown, width: 60)
        #expect(o.h.model.picture?.annotationReports[id]?.status == .held)
        #expect(o.h.model.remembered[id]?.values.first.map { abs($0 - 60) < 1e-9 } == true)
    }

    @Test func rememberMergesWithoutRemoving() {
        let h = EditorHarness(document: EditorDocuments.document([DrawingSheet(name: "Sheet 1")]), sheet: nil)
        let (a, b) = (AnnotationID(), AnnotationID())
        let figure = AnnotationFigure.leaders([])
        h.model.remember([a: LastGood(values: [1], lines: ["1"], figure: figure)])
        h.model.remember([b: LastGood(values: [2], lines: ["2"], figure: figure)])
        #expect(h.model.remembered[a]?.values == [1] && h.model.remembered[b]?.values == [2])
        h.model.remember([a: LastGood(values: [3], lines: ["3"], figure: figure)])
        #expect(h.model.remembered[a]?.values == [3], "an entry is replaced")
        #expect(h.model.remembered[b]?.values == [2], "the others stay")
        h.model.remember([:])
        #expect(h.model.remembered.count == 2)
    }
}

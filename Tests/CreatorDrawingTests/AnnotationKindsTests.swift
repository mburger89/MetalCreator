import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Annotation kinds and notes")
struct AnnotationKindsTests {
    private typealias Fixtures = AnnotationFixtures
    private let topology = Fixtures.topology()

    private func close(_ a: Vector2, _ b: Vector2, _ tolerance: Double = 1e-9) -> Bool { LayoutSupport.close(a, b, tolerance) }

    // MARK: Other kinds

    @Test func aHoleCallout() throws {
        let view = Fixtures.makeView()
        let callout = DrawingAnnotation(
            view: view.id,
            kind: .holeCallout(
                HoleCallout(anchor: Fixtures.pick(topology, 0), placement: DimensionPlacement(offset: 10, angle: 0.7))))
        let picture = Fixtures.compose(view, [callout], content: Fixtures.content())
        #expect(Fixtures.texts(picture, of: callout.id).map(\.original) == ["Ø6 THRU"])
        #expect(picture.fills.contains { $0.annotation == callout.id })
        let report = try #require(picture.annotationReports[callout.id])
        #expect(report.status == .held && report.label == "Ø6 THRU")
        #expect(report.current?.figure == .hole(center: Vector2(20, 10), radius: 3))
    }

    @Test func aBlindHoleCalloutDrawsItsSymbol() throws {
        let blind = Fixtures.topology(blind: true)
        let view = Fixtures.makeView()
        let callout = DrawingAnnotation(
            view: view.id,
            kind: .holeCallout(
                HoleCallout(anchor: Fixtures.pick(blind, 0), placement: DimensionPlacement(offset: 10, angle: 0.7))))
        let picture = Fixtures.compose(view, [callout], content: Fixtures.content(blind))
        let strokes = Fixtures.strokes(picture, of: callout.id)
        #expect(strokes.contains { stroke in stroke.segments.contains { if case .polyline = $0 { true } else { false } } })
        #expect(picture.annotationReports[callout.id]?.label == "Ø6 ↧10")
    }

    @Test func aCentreLineRunsPastTheCylinder() throws {
        let view = Fixtures.makeView(orientation: .front)
        let face = try #require(topology.facePick(for: FaceID(2)))
        let line = DrawingAnnotation(view: view.id, kind: .centreLine(CentreLine(anchor: .axis(face))))
        let picture = Fixtures.compose(view, [line], content: Fixtures.content())
        let strokes = Fixtures.strokes(picture, of: line.id)
        #expect(strokes.count == 1)
        let stroke = try #require(strokes.first)
        #expect(stroke.layer == .center && stroke.pattern == .centre)
        guard case let .line(a, b)? = stroke.segments.first else {
            Issue.record("expected a line")
            return
        }
        #expect(abs((b - a).length - 24) < 1e-9)
    }

    @Test func aCentreLineOnACylinderWithNoCircularEdgesHoldsItsAnchor() throws {
        let view = Fixtures.makeView(orientation: .front)
        let face = try #require(topology.facePick(for: FaceID(2)))
        let line = DrawingAnnotation(view: view.id, kind: .centreLine(CentreLine(anchor: .axis(face))))
        let bare = Fixtures.topology(removing: [0, 1])
        let picture = Fixtures.compose(view, [line], content: Fixtures.content(bare))
        let report = try #require(picture.annotationReports[line.id])
        #expect(report.anchors == [.held])
        guard case .lost(let reason) = report.status else {
            Issue.record("expected lost")
            return
        }
        #expect(reason != .missing)
    }

    @Test func aCentreMarkAnnotationMarksACircle() {
        let view = Fixtures.makeView()
        let mark = DrawingAnnotation(view: view.id, kind: .centreMark(CentreMark(anchor: Fixtures.pick(topology, 0))))
        let picture = Fixtures.compose(view, [mark], content: Fixtures.content())
        #expect(Fixtures.strokes(picture, of: mark.id).count == 2)
        #expect(picture.annotationReports[mark.id]?.current?.figure == .centreMark(center: Vector2(20, 10), radius: 3))
    }

    // MARK: Notes

    @Test func aNoteDrawsItsLines() {
        let view = Fixtures.makeView()
        let note = Fixtures.note(view.id, "First\nSecond", at: Vector2(10, -5))
        let picture = Fixtures.compose(view, [note], content: Fixtures.content())
        let texts = Fixtures.texts(picture, of: note.id)
        #expect(texts.map(\.original) == ["First", "Second"])
        #expect(texts.allSatisfy { $0.layer == .text && $0.view == view.id })
        let h = DrawingStyle.iso.notesHeight(for: .a3)
        #expect(abs((texts[0].origin.y - texts[1].origin.y) - 1.6 * h) < 1e-9)
        // The top line's cap is at the position, which is relative to the view's centre.
        #expect(close(texts[0].origin, Vector2(160, 145 - h)))
        #expect(picture.annotationReports[note.id]?.status == .held)
    }

    @Test func aNoteLeaderEndsOnItsEdge() throws {
        let view = Fixtures.makeView()
        let leader = LeaderEnd(target: Fixtures.pick(topology, 100), hint: Vector2(25, 5))
        let note = Fixtures.note(view.id, "Edge", at: Vector2(40, 20), leaders: [leader])
        let picture = Fixtures.compose(view, [note], content: Fixtures.content())
        // The edge runs from model (20, 0) to (20, 20); the view maps model (20, 10) to (150, 150).
        let tip = Vector2(150, 145)
        #expect(picture.fills.contains { $0.annotation == note.id && $0.points.contains { close($0, tip) } })
        let report = try #require(picture.annotationReports[note.id])
        #expect(report.anchors == [.held])
        #expect(report.current?.figure == .leaders([Vector2(20, 5)]))
        #expect(picture.lostAnnotations.isEmpty)
    }

    @Test func aLostLeaderDrawsToItsLastPointAndTheNoteStaysHeld() throws {
        let view = Fixtures.makeView()
        let leader = LeaderEnd(target: Fixtures.pick(topology, 100), hint: Vector2(25, 5))
        let note = Fixtures.note(view.id, "Edge", at: Vector2(40, 20), leaders: [leader])
        let last = LastGood(values: [], lines: ["Edge"], figure: .leaders([Vector2(20, 7)]))
        let picture = Fixtures.compose(
            view, [note], content: Fixtures.content(Fixtures.topology(removing: [100])), remembered: [note.id: last])
        let report = try #require(picture.annotationReports[note.id])
        #expect(report.status == .held)
        #expect(report.anchors == [.lost(.missing)])
        #expect(picture.lostAnnotations.isEmpty)
        let tip = Vector2(150, 147)
        #expect(picture.fills.contains { $0.annotation == note.id && $0.points.contains { close($0, tip) } })
    }

    @Test func aFreeNoteIsAbsolute() {
        let view = Fixtures.makeView()
        let note = Fixtures.note(nil, "Free", at: Vector2(30, 40))
        let picture = Fixtures.compose(view, [note], content: Fixtures.content())
        let texts = Fixtures.texts(picture, of: note.id)
        let h = DrawingStyle.iso.notesHeight(for: .a3)
        #expect(texts.count == 1 && texts[0].view == nil)
        #expect(close(texts[0].origin, Vector2(30, 40 - h)))
        #expect(picture.annotationReports[note.id]?.status == .held)
    }

    @Test func aFreeNoteLeaderPointIsAbsolute() {
        let view = Fixtures.makeView()
        let leader = LeaderEnd(target: .point(Vector2(100, 80)), hint: .zero)
        let note = Fixtures.note(nil, "Free", at: Vector2(30, 40), leaders: [leader])
        let picture = Fixtures.compose(view, [note], content: Fixtures.content())
        #expect(picture.fills.contains { $0.annotation == note.id && $0.points.contains { close($0, Vector2(100, 80)) } })
    }

    @Test func aViewNoteSurvivesAViewWithNoPart() {
        let view = Fixtures.makeView()
        let note = Fixtures.note(view.id, "Kept", at: Vector2(0, 0))
        let picture = Fixtures.compose(view, [note], content: ViewContent(problem: DrawingProjector.removedSentence))
        #expect(Fixtures.texts(picture, of: note.id).map(\.original) == ["Kept"])
        #expect(picture.lostAnnotations.isEmpty)
    }
}

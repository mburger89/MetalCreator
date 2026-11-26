import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The Balloon tool: a first click names a line of a part, the next places the circle (DR-5 R4, R16).
@MainActor
@Suite("Balloon tool")
struct BalloonToolTests {
    private func balloon(_ s: AssemblyScene) throws -> (DrawingAnnotation, Balloon) {
        let all = s.annotations
        #expect(all.count == 1, "\(all.count) annotations")
        let one = try #require(all.first)
        guard case .balloon(let value) = one.kind else {
            Issue.record("not a balloon")
            throw CancellationError()
        }
        return (one, value)
    }

    @Test func aBalloonOnALine() throws {
        let s = AssemblyScene.make()
        s.h.model.press(.balloon)
        s.click(s.at(108, 0))
        #expect(s.h.model.balloonDraft != nil, "\(s.h.model.refusal ?? "")")
        #expect(s.h.log.commits.isEmpty, "a target is not an edit")
        let foot = s.at(108, 0)
        s.click(foot + Vector2(15, 15))
        #expect(s.h.log.commits.map(\.name) == ["Add Balloon"])
        let (annotation, made) = try balloon(s)
        #expect(made.leader.target == s.pick(1102, copy: 1))
        #expect((made.offset - Vector2(15, 15)).length < 1e-6, "\(made.offset)")
        #expect(annotation.view == s.view.id)
        #expect(s.h.model.selectedAnnotations == [annotation.id])
        #expect(s.h.model.tool == .balloon, "the tool stays")
        #expect(s.h.model.balloonDraft == nil)
    }

    @Test func aBalloonInASingleView() throws {
        let scene = SelectionScene.make([])
        let at = { (x: Double, y: Double) in scene.mapping.sheet(Vector2(x, y)) }
        scene.h.model.press(.balloon)
        scene.h.click(at(8, 0).x, at(8, 0).y)
        scene.h.click(at(8, -10).x, at(8, -10).y)
        #expect(scene.h.log.commits.map(\.name) == ["Add Balloon"], "\(scene.h.model.refusal ?? "")")
        guard case .balloon(let made)? = scene.h.model.document.sheets[0].annotations.first?.kind else {
            Issue.record("not a balloon")
            return
        }
        #expect(made.leader.target == SelectionScene.Fixtures.pick(SelectionScene.Fixtures.topology(), 102))
        #expect(made.leader.target.part == nil)
    }

    @Test func isometricViewsTakeBalloons() throws {
        let scene = SelectionScene.make([])
        var sheet = scene.h.model.document.sheets[0]
        var view = sheet.views[0]
        view.orientation = .standard(.isometricFrontRight)
        sheet.setView(view)
        scene.h.model.replaceDocument(EditorDocuments.document([sheet]))
        let at = { (x: Double, y: Double) in scene.mapping.sheet(Vector2(x, y)) }
        scene.h.model.press(.balloon)
        scene.h.click(at(8, 0).x, at(8, 0).y)
        scene.h.click(at(8, -10).x, at(8, -10).y)
        #expect(scene.h.log.commits.map(\.name) == ["Add Balloon"], "\(scene.h.model.refusal ?? "")")
    }

    @Test func aBalloonRefusesAFreeCurve() throws {
        let s = AssemblyScene.make(curve: true)
        s.h.model.press(.balloon)
        s.click(s.at(20, 60))
        #expect(s.h.model.refusal == "This line is a free curve; balloons attach to a part's edges.")
        #expect(s.h.model.balloonDraft == nil)
        #expect(s.h.log.commits.isEmpty)
    }

    @Test func escapeDropsTheTargetThenTheTool() throws {
        let s = AssemblyScene.make()
        s.h.model.press(.balloon)
        s.click(s.at(8, 0))
        #expect(s.h.model.balloonDraft != nil)
        #expect(s.h.model.keyPressed(.escape))
        #expect(s.h.model.balloonDraft == nil && s.h.model.tool == .balloon)
        #expect(s.h.model.keyPressed(.escape))
        #expect(s.h.model.tool == .select)
    }

    @Test func theDraftFollowsThePointer() throws {
        let s = AssemblyScene.make()
        s.h.model.press(.balloon)
        s.click(s.at(8, 0))
        let id = s.h.model.draftID
        var frames: [Rect2D] = []
        for point in [s.at(8, 0) + Vector2(10, 10), s.at(8, 0) + Vector2(30, 5)] {
            s.h.model.pointerMoved(to: s.h.canvas(point.x, point.y))
            let report = try #require(s.h.model.draftPicture?.annotationReports[id])
            #expect(report.frame.contains(point), "the circle is under the pointer")
            frames.append(report.frame)
        }
        #expect(frames[0] != frames[1])
        #expect(s.h.log.commits.isEmpty, "a draft is not an edit")
    }

    private func made() -> AssemblyScene {
        AssemblyScene.make(annotations: [
            { first, _ in
                AssemblyScene.balloonAnnotation(on: first, edge: 102, copy: 0, offset: Vector2(8, -12))
            },
        ])
    }

    @Test func draggingABalloonMovesItsOffset() throws {
        let s = made()
        let report = try #require(s.h.model.picture?.annotationReports[s.annotations[0].id])
        let centre = report.textCenter ?? report.frame.center
        s.h.model.pointerDown(at: s.h.canvas(centre.x, centre.y), modifiers: [])
        s.h.model.pointerDragged(to: s.h.canvas(centre.x + 5, centre.y + 2))
        s.h.model.pointerDragged(to: s.h.canvas(centre.x + 10, centre.y + 4))
        s.h.model.pointerUp(at: s.h.canvas(centre.x + 10, centre.y + 4))
        #expect(!s.h.log.commits.isEmpty && s.h.log.commits.allSatisfy { $0.name == "Move Balloon" })
        #expect(Set(s.h.log.commits.map(\.coalescingKey)).count == 1)
        let (_, moved) = try balloon(s)
        #expect((moved.offset - Vector2(18, -8)).length < 1e-6, "\(moved.offset)")
    }

    @Test func nudgingABalloon() throws {
        let s = made()
        s.h.model.selectedAnnotations = [s.annotations[0].id]
        s.h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: false))
        #expect(s.h.log.commits.map(\.name) == ["Move Balloon"])
        let (_, moved) = try balloon(s)
        #expect((moved.offset - Vector2(9, -12)).length < 1e-6)
    }

    @Test func deletingABalloon() throws {
        let s = made()
        s.h.model.selectedAnnotations = [s.annotations[0].id]
        s.h.model.deleteSelection()
        #expect(s.h.log.commits.map(\.name) == ["Delete Balloon"])
        #expect(s.annotations.isEmpty)
    }

    @Test func aMixIsMoveAnnotations() throws {
        let s = AssemblyScene.make(annotations: [
            { first, _ in AssemblyScene.balloonAnnotation(on: first, edge: 102, copy: 0, offset: Vector2(8, -12)) },
            { _, _ in DrawingAnnotation(view: nil, kind: .note(DrawingNote(text: "Plate", position: Vector2(60, -10)))) },
        ])
        s.h.model.selectedAnnotations = Set(s.annotations.map(\.id))
        s.h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: false))
        #expect(s.h.log.commits.map(\.name) == ["Move Annotations"])
        s.h.model.deleteSelection()
        #expect(s.h.log.commits.map(\.name) == ["Move Annotations", "Delete Annotations"])
    }
}

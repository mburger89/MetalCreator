import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Moving, nudging and deleting symbols (plan R16): a symbol slides along its line, a frame changes its offset, and a symbol
/// whose dimension moves in the same gesture stays where it hangs.
@MainActor
@Suite("Symbol selection")
struct SymbolSelectionTests {
    private typealias Scene = SelectionScene
    private typealias Fixtures = AnnotationEditorFixtures

    private static let datumID = AnnotationID()
    private static let frameID = AnnotationID()
    private static let surfaceID = AnnotationID()
    private static let hangingID = AnnotationID()

    private static var bottom: LeaderEnd {
        LeaderEnd(target: Fixtures.pick(Fixtures.topology(), 102), hint: Vector2(8, 0))
    }

    private func scene(_ pieces: [Scene.Piece] = [], adding symbols: [DrawingAnnotation]) -> Scene {
        let s = Scene.make(pieces)
        var placed = symbols
        for index in placed.indices { placed[index].view = s.view.id }
        s.h.model.commitSheet("Setup") { sheet in for symbol in placed { sheet.setAnnotation(symbol) } }
        s.h.log.commits.removeAll()
        return s
    }

    private static func datum(distance: Double = -10) -> DrawingAnnotation {
        DrawingAnnotation(
            id: datumID, view: nil,
            kind: .datumFeature(DatumFeature(letter: "A", attachment: .feature(bottom), distance: distance)))
    }

    private static func frame(on attachment: SymbolAttachment? = nil, offset: Vector2 = Vector2(5, -6)) -> DrawingAnnotation {
        DrawingAnnotation(
            id: frameID, view: nil,
            kind: .featureControl(
                FeatureControlFrame(
                    characteristic: .flatness, rows: [ToleranceRow(value: 0.05)], attachment: attachment ?? .feature(bottom),
                    offset: offset)))
    }

    private static func surface(offset: Vector2?) -> DrawingAnnotation {
        DrawingAnnotation(
            id: surfaceID, view: nil,
            kind: .surfaceTexture(
                SurfaceTexture(
                    requirement: SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 3.2), feature: bottom,
                    offset: offset)))
    }

    private func datum(_ s: Scene) throws -> DatumFeature {
        guard case .datumFeature(let value)? = s.annotation(Self.datumID)?.kind else { throw CancellationError() }
        return value
    }

    private func frame(_ s: Scene) throws -> FeatureControlFrame {
        guard case .featureControl(let value)? = s.annotation(Self.frameID)?.kind else { throw CancellationError() }
        return value
    }

    private func texture(_ s: Scene) throws -> SurfaceTexture {
        guard case .surfaceTexture(let value)? = s.annotation(Self.surfaceID)?.kind else { throw CancellationError() }
        return value
    }

    @Test func draggingADatumSlidesItsFoot() throws {
        let s = scene(adding: [Self.datum()])
        let held = try #require(s.report[Self.datumID])
        #expect(held.status == .held, "\(held.status)")
        s.drag(from: s.centre(of: Self.datumID), by: Vector2(5, -3))
        #expect(Set(s.h.log.commits.map(\.name)) == ["Move Symbol"])
        #expect(Set(s.h.log.commits.map(\.coalescingKey)).count == 1, "one undo step")
        let moved = try datum(s)
        guard case .feature(let end) = moved.attachment else {
            Issue.record("expected a line")
            return
        }
        #expect(abs(end.hint.x - 13) < 1e-6 && abs(end.hint.y) < 1e-6, "\(end.hint)")
        #expect(abs(moved.distance - (-13)) < 1e-6, "\(moved.distance)")
    }

    @Test func draggingAFrameMovesItsOffset() throws {
        let s = scene(adding: [Self.frame()])
        s.drag(from: s.centre(of: Self.frameID), by: Vector2(4, 2))
        #expect(Set(s.h.log.commits.map(\.name)) == ["Move Symbol"])
        let moved = try frame(s)
        #expect((moved.offset - Vector2(9, -4)).length < 1e-6, "\(moved.offset)")
    }

    @Test func draggingAStandingSurfaceSymbolSlidesIt() throws {
        let s = scene(adding: [Self.surface(offset: nil)])
        s.drag(from: s.centre(of: Self.surfaceID), by: Vector2(6, 2))
        let moved = try texture(s)
        #expect(moved.offset == nil, "it still stands")
        #expect(abs(moved.feature.hint.x - 14) < 1e-6, "\(moved.feature.hint)")
    }

    @Test func draggingASurfaceSymbolOnALeaderChangesItsOffset() throws {
        let s = scene(adding: [Self.surface(offset: Vector2(2, -8))])
        s.drag(from: s.centre(of: Self.surfaceID), by: Vector2(3, -1))
        let moved = try texture(s)
        let offset = try #require(moved.offset)
        #expect((offset - Vector2(5, -9)).length < 1e-6, "\(offset)")
        #expect(abs(moved.feature.hint.x - 8) < 1e-9, "the foot stays")
    }

    @Test func aSymbolMovesWithItsDimensionOnce() throws {
        let s = scene([.horizontal], adding: [Self.frame(on: .dimension(Scene.horizontal), offset: Vector2(1, 1))])
        #expect(s.report[Self.frameID]?.status == .held)
        s.h.model.selectedAnnotations = [Scene.horizontal, Self.frameID]
        s.drag(from: s.label(of: Scene.horizontal), by: Vector2(0, -5))
        let moved = try #require(s.dimension(Scene.horizontal))
        #expect(abs(moved.placement.offset - 5) < 1e-9, "\(moved.placement.offset)")
        #expect(try frame(s).offset == Vector2(1, 1), "the frame follows its dimension and is not moved again")
    }

    @Test func aLostFrameOnADimensionStillLetsAClickSelectTheDimension() throws {
        let held = Scene.make([.horizontal])
        let last = try #require(held.h.model.remembered[Scene.horizontal])
        let s = Scene.make([.horizontal], removing: [103])
        s.h.model.commitSheet("Setup") { sheet in
            var placed = Self.frame(on: .dimension(Scene.horizontal), offset: Vector2(1, 1))
            placed.view = s.view.id
            sheet.setAnnotation(placed)
            if var dimension = sheet.annotation(Scene.horizontal) {
                dimension.last = last
                sheet.setAnnotation(dimension)
            }
        }
        s.h.log.commits.removeAll()
        #expect(s.report[Self.frameID]?.isLost == true)
        s.h.model.selectedAnnotations = [Self.frameID]
        // A press inside the view that is on no line is a plain select, not a refusal.
        let box = try #require(s.h.model.picture?.viewFrames[s.view.id])
        var found: Vector2?
        for row in 1..<20 {
            for column in 1..<40 where found == nil {
                let point = box.min + Vector2(Double(column), Double(row)) * 0.99
                if s.h.model.viewUnder(point) == s.view.id, !s.h.model.reattachClick(at: point) { found = point }
            }
        }
        s.h.model.refusal = nil
        let inside = try #require(found, "a spot in the view that is on no line")
        s.h.click(inside.x, inside.y)
        #expect(s.h.model.refusal == nil, "\(s.h.model.refusal ?? "")")
        #expect(s.h.model.selectedAnnotations.isEmpty, "\(s.h.model.selectedAnnotations)")
        #expect(s.h.model.selection == [s.view.id])
        // Selected again, the frame can be dragged by its own box.
        s.h.model.selectedAnnotations = [Self.frameID]
        let label = try #require(s.report[Scene.horizontal]?.textCenter)
        s.h.click(label.x, label.y)
        #expect(
            s.h.model.selectedAnnotations == [Scene.horizontal], "\(s.h.model.selectedAnnotations) \(s.h.model.refusal ?? "")")
    }

    @Test func aHangingDatumChangesItsDistanceByTheDownwardPart() throws {
        let s = Scene.make([.diameter])
        s.h.model.document.settings.standard = .asme
        s.h.model.commitSheet("Setup") { sheet in
            sheet.setAnnotation(
                DrawingAnnotation(
                    id: Self.datumID, view: s.view.id,
                    kind: .datumFeature(DatumFeature(letter: "A", attachment: .dimension(Scene.diameter), distance: 12))))
        }
        s.h.log.commits.removeAll()
        let report = try #require(s.report[Self.datumID])
        #expect(report.status == .held, "\(report.status)")
        #expect(s.report[Scene.diameter]?.dimensionLine == nil, "an ASME diameter has no dimension line")
        s.drag(from: s.centre(of: Self.datumID), by: Vector2(0, -4))
        #expect(Set(s.h.log.commits.map(\.name)) == ["Move Symbol"])
        #expect(abs(try datum(s).distance - 16) < 1e-6)
    }

    @Test func aDatumOnADimensionLineMovesToTheNearerEnd() throws {
        let s = scene(
            [.horizontal],
            adding: [
                DrawingAnnotation(
                    id: Self.datumID, view: nil,
                    kind: .datumFeature(
                        DatumFeature(letter: "A", attachment: .dimension(Scene.horizontal), distance: 12, dimensionEnd: 0))),
            ])
        let tips = try #require(s.report[Scene.horizontal]?.dimensionLine)
        #expect(tips.count == 2)
        func outward(_ end: Int) -> Vector2 {
            let v = tips[end] - tips[1 - end]
            return v * (1 / v.length)
        }
        let from = tips[0] + outward(0) * 12
        let to = tips[1] + outward(1) * 15
        s.drag(from: s.centre(of: Self.datumID), by: to - from)
        let moved = try datum(s)
        #expect(moved.dimensionEnd == 1, "\(moved)")
        #expect(abs(moved.distance - 15) < 1e-6, "\(moved.distance)")
    }

    @Test func nudgingSymbols() throws {
        let s = scene(adding: [Self.frame()])
        s.h.model.selectedAnnotations = [Self.frameID]
        #expect(s.h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: false)))
        #expect(s.h.log.commits.map(\.name) == ["Move Symbol"])
        #expect((try frame(s).offset - Vector2(6, -6)).length < 1e-9)
    }

    @Test func aMixOfMovesStaysMoveAnnotations() throws {
        let s = scene([.note], adding: [Self.frame()])
        s.h.model.selectedAnnotations = [Self.frameID, Scene.note]
        #expect(s.h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: false)))
        #expect(s.h.log.commits.map(\.name) == ["Move Annotations"])
    }

    @Test func deletingADimensionDeletesItsSymbolsInOneStep() throws {
        let s = scene([.horizontal], adding: [Self.frame(on: .dimension(Scene.horizontal), offset: .zero)])
        let before = s.h.model.document
        s.h.model.selectedAnnotations = [Scene.horizontal]
        s.h.model.deleteSelection()
        #expect(s.h.log.commits.map(\.name) == ["Delete Dimension"])
        #expect(s.h.model.document.sheets[0].annotations.isEmpty)
        s.h.model.replaceDocument(before)
        #expect(s.h.model.document.sheets[0].annotations.count == 2, "undo brings both")
    }

    @Test func deletingSymbolsIsDeleteSymbol() throws {
        let s = scene(adding: [Self.datum(), Self.frame(), Self.surface(offset: nil)])
        s.h.model.selectedAnnotations = [Self.datumID, Self.frameID, Self.surfaceID]
        s.h.model.deleteSelection()
        #expect(s.h.log.commits.map(\.name) == ["Delete Symbol"])
        #expect(s.h.model.document.sheets[0].annotations.isEmpty)
    }

    @Test func aMixOfDeletesStaysDeleteAnnotations() throws {
        let s = scene([.note], adding: [Self.frame()])
        s.h.model.selectedAnnotations = [Self.frameID, Scene.note]
        s.h.model.deleteSelection()
        #expect(s.h.log.commits.map(\.name) == ["Delete Annotations"])
    }
}

import Foundation
import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The Datum, Feature Control Frame and Surface Finish tools: a first click names the target, the next places the symbol
/// (plan R15, R17), over the part seen from the top at 4 points per millimetre.
@MainActor
@Suite("Symbol tools")
struct SymbolToolTests {
    private typealias Scene = SelectionScene

    private func open(_ pieces: [Scene.Piece] = []) -> Scene {
        Scene.make(pieces)
    }

    private func at(_ s: Scene, _ x: Double, _ y: Double) -> Vector2 { s.mapping.sheet(Vector2(x, y)) }

    private func click(_ s: Scene, _ point: Vector2, _ modifiers: SheetModifiers = []) {
        s.h.click(point.x, point.y, modifiers)
    }

    private var annotations: (Scene) -> [DrawingAnnotation] { { $0.h.model.document.sheets[0].annotations } }

    private func only(_ s: Scene) throws -> DrawingAnnotation {
        let all = annotations(s)
        #expect(all.count == 1, "\(all.count) annotations")
        return try #require(all.first)
    }

    private func datum(_ s: Scene) throws -> DatumFeature {
        guard case .datumFeature(let value) = try only(s).kind else {
            Issue.record("not a datum")
            throw CancellationError()
        }
        return value
    }

    private func frame(_ s: Scene) throws -> FeatureControlFrame {
        guard case .featureControl(let value) = try only(s).kind else {
            Issue.record("not a frame")
            throw CancellationError()
        }
        return value
    }

    private func texture(_ s: Scene) throws -> SurfaceTexture {
        guard case .surfaceTexture(let value) = try only(s).kind else {
            Issue.record("not a surface symbol")
            throw CancellationError()
        }
        return value
    }

    // MARK: Datum

    @Test func aDatumOnALine() throws {
        let s = open()
        s.h.model.press(.datum)
        click(s, at(s, 8, 0))
        #expect(s.h.model.symbolDraft != nil, "\(s.h.model.refusal ?? "")")
        #expect(s.h.log.commits.isEmpty, "a target is not an edit")
        click(s, at(s, 8, -10))
        #expect(s.h.log.commits.map(\.name) == ["Add Datum"])
        let made = try datum(s)
        #expect(made.letter == "A")
        #expect(abs(made.distance - (-10)) < 1e-9)
        guard case .feature(let end) = made.attachment else {
            Issue.record("expected a line: \(made.attachment)")
            return
        }
        #expect(end.target == Scene.Fixtures.pick(Scene.Fixtures.topology(), 102))
        #expect(s.h.model.selectedAnnotations == [try only(s).id])
        #expect(s.h.model.tool == .datum, "the tool stays")
        #expect(s.h.model.symbolDraft == nil)
    }

    @Test func theNextDatumIsB() throws {
        let s = open()
        s.h.model.press(.datum)
        click(s, at(s, 8, 0))
        click(s, at(s, 8, -10))
        click(s, at(s, 10, 0.2))
        click(s, at(s, 10, 8))
        let letters = s.h.model.document.sheets[0].annotations.compactMap { annotation -> String? in
            if case .datumFeature(let datum) = annotation.kind { datum.letter } else { nil }
        }
        #expect(letters.sorted() == ["A", "B"], "\(letters) \(s.h.model.refusal ?? "")")
    }

    @Test func aDatumOnADimension() throws {
        let s = open([.horizontal])
        s.h.model.press(.datum)
        click(s, s.label(of: Scene.horizontal))
        #expect(s.h.model.symbolDraft?.target == .dimension(Scene.horizontal), "\(s.h.model.refusal ?? "")")
        let tips = try #require(s.report[Scene.horizontal]?.dimensionLine)
        #expect(tips.count == 2)
        let spot = tips[1] + Vector2(3, 3)
        click(s, spot)
        #expect(s.h.log.commits.map(\.name) == ["Add Datum"])
        let made = try #require(s.h.model.document.sheets[0].annotations.first { $0.id != Scene.horizontal })
        guard case .datumFeature(let datum) = made.kind else {
            Issue.record("expected a datum")
            return
        }
        #expect(datum.attachment == .dimension(Scene.horizontal))
        #expect(datum.dimensionEnd == ((tips[1] - spot).length < (tips[0] - spot).length ? 1 : 0))
        #expect(datum.dimensionEnd == 1)
        #expect(made.view == s.view.id)
    }

    @Test func aDatumRefusesAnAngle() throws {
        let full = Scene.Fixtures.topology()
        let angle = DrawingAnnotation(
            view: nil,
            kind: .dimension(
                DrawingDimension(
                    kind: .angle, anchors: [Scene.Fixtures.pick(full, 102), Scene.Fixtures.pick(full, 105)],
                    placement: DimensionPlacement(offset: 8, angle: 0.3))))
        let s = open()
        var placed = angle
        placed.view = s.view.id
        s.h.model.commitSheet("Add Dimension") { $0.setAnnotation(placed) }
        s.h.log.commits.removeAll()
        s.h.model.press(.datum)
        click(s, s.label(of: placed.id))
        #expect(s.h.model.symbolDraft == nil)
        #expect(s.h.model.refusal == "A datum symbol goes on a size: a linear dimension, a diameter or a hole callout.")
    }

    // MARK: Frame

    @Test func aFrameOnALine() throws {
        let s = open()
        s.h.model.press(.featureControlFrame)
        click(s, at(s, 8, 0))
        click(s, at(s, 13, -6))
        #expect(s.h.log.commits.map(\.name) == ["Add Feature Control Frame"], "\(s.h.model.refusal ?? "")")
        let made = try frame(s)
        #expect(made.characteristic == .flatness)
        #expect(made.rows == [ToleranceRow(zone: .width, value: 0.05)])
        #expect((made.offset - Vector2(5, -6)).length < 1e-9, "\(made.offset)")
    }

    @Test func theNextFrameCopiesTheLast() throws {
        let s = open()
        let template = FeatureControlFrame(
            characteristic: .perpendicularity,
            rows: [ToleranceRow(zone: .diameter, value: 0.2, material: .maximum, datums: [DatumReference(letter: "A")])],
            attachment: .dimension(AnnotationID()), offset: Vector2(99, 99))
        s.h.model.frameTemplate = template
        s.h.model.press(.featureControlFrame)
        click(s, at(s, 8, 0))
        click(s, at(s, 13, -6))
        let made = try frame(s)
        #expect(made.characteristic == .perpendicularity)
        #expect(made.rows == template.rows)
        #expect((made.offset - Vector2(5, -6)).length < 1e-9, "the offset is the click's, not the template's")
        guard case .feature = made.attachment else {
            Issue.record("the attachment is the new target's")
            return
        }
        #expect(s.h.model.frameTemplate?.characteristic == .perpendicularity)
    }

    @Test func aFirstFrameBecomesTheTemplate() throws {
        let s = open()
        #expect(s.h.model.frameTemplate == nil)
        s.h.model.press(.featureControlFrame)
        click(s, at(s, 8, 0))
        click(s, at(s, 13, -6))
        #expect(s.h.model.frameTemplate?.characteristic == .flatness)
    }

    @Test func aFrameOnTheHole() throws {
        let s = open()
        s.h.model.press(.featureControlFrame)
        click(s, at(s, 23, 10))
        #expect(s.h.model.symbolDraft != nil, "\(s.h.model.refusal ?? "")")
        click(s, at(s, 30, 22))
        #expect(s.h.log.commits.map(\.name) == ["Add Feature Control Frame"])
        let made = try frame(s)
        guard case .feature(let end) = made.attachment else {
            Issue.record("expected the circle: \(made.attachment)")
            return
        }
        #expect(end.target == Scene.Fixtures.pick(Scene.Fixtures.topology(), 0))
    }

    @Test func aFrameOnADimension() throws {
        let s = open([.horizontal])
        s.h.model.press(.featureControlFrame)
        click(s, s.label(of: Scene.horizontal))
        #expect(s.h.model.symbolDraft?.target == .dimension(Scene.horizontal))
        let rect = try #require(s.report[Scene.horizontal]?.labelRect)
        let gap = AnnotationStyle.of(s.h.model.document.settings.standard).textGap
        click(s, Vector2(rect.min.x, rect.min.y - gap))
        let made = try #require(s.h.model.document.sheets[0].annotations.first { $0.id != Scene.horizontal })
        guard case .featureControl(let frame) = made.kind else {
            Issue.record("expected a frame")
            return
        }
        #expect(frame.attachment == .dimension(Scene.horizontal))
        #expect(frame.offset.length < 1e-9, "\(frame.offset)")
    }

    /// The composer stacks frames on a dimension in id order, so a second frame lands where its click said whichever id it has.
    @Test(arguments: [true, false])
    func aSecondFrameOnADimensionLandsAtTheClick(newSortsAfter: Bool) throws {
        let s = open([.horizontal])
        let low = AnnotationID(rawValue: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
        let high = AnnotationID(rawValue: try #require(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")))
        let first = newSortsAfter ? low : high
        let second = newSortsAfter ? high : low
        s.h.model.commitSheet("Setup") { sheet in
            let frame = FeatureControlFrame(
                characteristic: .flatness, rows: [ToleranceRow(zone: .width, value: 0.05)], attachment: .dimension(Scene.horizontal))
            sheet.setAnnotation(DrawingAnnotation(id: first, view: s.view.id, kind: .featureControl(frame)))
        }
        s.h.log.commits.removeAll()
        let existing = try #require(s.report[first]?.frame)
        let gap = AnnotationStyle.of(s.h.model.document.settings.standard).textGap
        s.h.model.press(.featureControlFrame)
        click(s, s.label(of: Scene.horizontal))
        s.h.model.symbolDraft?.id = second
        let target = Vector2(existing.min.x, existing.min.y - gap - 1)
        click(s, target)
        let placed = try #require(s.report[second]?.frame)
        #expect(abs(placed.min.x - target.x) < 1e-6 && abs(placed.max.y - target.y) < 1e-6, "\(placed) for \(target)")
    }

    // MARK: Surface

    @Test func aSurfaceSymbolStandsOnATopLine() throws {
        let s = open()
        s.h.model.press(.surfaceFinish)
        click(s, at(s, 10, 0))
        click(s, at(s, 10, 2))
        #expect(s.h.log.commits.map(\.name) == ["Add Surface Symbol"], "\(s.h.model.refusal ?? "")")
        let made = try texture(s)
        #expect(made.offset == nil)
        #expect(made.requirement == SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 3.2))
        #expect(made.lay == nil)
        #expect(s.h.model.surfaceTemplate == made)
    }

    @Test func aSurfaceSymbolOnALeader() throws {
        let s = open()
        s.h.model.press(.surfaceFinish)
        click(s, at(s, 10, 0))
        click(s, at(s, 14, -6))
        let made = try texture(s)
        let offset = try #require(made.offset)
        #expect((offset - Vector2(4, -6)).length < 1e-9, "\(offset)")
    }

    @Test func aSurfaceSymbolFarAboveTheLineTakesALeader() throws {
        let s = open()
        s.h.model.press(.surfaceFinish)
        click(s, at(s, 10, 0))
        click(s, at(s, 10, 8))
        #expect(try texture(s).offset != nil, "8 mm is beyond the snap")
    }

    @Test func theNextSurfaceSymbolCopiesTheLast() throws {
        let s = open()
        let template = SurfaceTexture(
            requirement: SurfaceRequirement(process: .removalProhibited, parameter: .rz, value: 6.3), lay: .crossed,
            feature: LeaderEnd(target: .point(.zero), hint: .zero), offset: Vector2(9, 9))
        s.h.model.surfaceTemplate = template
        s.h.model.press(.surfaceFinish)
        click(s, at(s, 10, 0))
        click(s, at(s, 10, 2))
        let made = try texture(s)
        #expect(made.requirement == template.requirement)
        #expect(made.lay == .crossed)
        #expect(made.offset == nil)
    }

    @Test func aSurfaceSymbolRefusesADimension() throws {
        let s = open([.horizontal])
        s.h.model.press(.surfaceFinish)
        click(s, s.label(of: Scene.horizontal))
        #expect(s.h.model.symbolDraft == nil)
        #expect(s.h.model.refusal == "A surface symbol stands on a straight line of a view.")
    }
}

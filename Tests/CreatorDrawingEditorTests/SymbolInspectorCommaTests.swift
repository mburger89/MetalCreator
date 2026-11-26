import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// A document with a comma decimal sign shows its lengths with a comma, so the setters read one (DR-4 final review).
@MainActor
@Suite("Symbol inspector commas")
struct SymbolInspectorCommaTests {
    private typealias Fixtures = AnnotationEditorFixtures
    private static let frameID = AnnotationID()

    @Test func lengthFieldsTakeTheCommaTheyAreShownWith() {
        let s = SelectionScene.make([])
        let end = LeaderEnd(target: Fixtures.pick(Fixtures.topology(), 102), hint: Vector2(8, 0))
        let frame = FeatureControlFrame(
            characteristic: .position, rows: [ToleranceRow(zone: .diameter, value: 0.1)], attachment: .feature(end))
        let symbol = DrawingAnnotation(id: Self.frameID, view: s.view.id, kind: .featureControl(frame))
        s.h.model.commitSheet("Setup") { $0.setAnnotation(symbol) }
        s.h.model.setToleranceValue(text: "0,25", row: 0, of: Self.frameID)
        #expect(s.h.model.refusal == nil)
        s.h.model.setProjectedZone(true, lengthText: "2,5", row: 0, of: Self.frameID)
        guard case .featureControl(let saved)? = s.h.model.sheet?.annotation(Self.frameID)?.kind else {
            Issue.record("no frame")
            return
        }
        #expect(saved.rows[0].value == 0.25)
        #expect(saved.rows[0].projected == ProjectedZone(length: 2.5))
    }
}

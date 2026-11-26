import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// `setDimensionKind` against the kind of measure and the symbols hanging on a dimension (DR-4 R2).
@MainActor
@Suite("Dimension kind and symbols")
struct DimensionKindSymbolTests {
    private typealias Scene = SelectionScene

    private func names(_ s: Scene) -> [String] { s.h.log.commits.map(\.name) }

    @Test func aMismatchedKindIsRefused() {
        let s = Scene.make([.horizontal])
        s.h.model.setDimensionKind(.radius, of: Scene.horizontal)
        #expect(
            s.h.model.refusal == "A dimension keeps its kind of measure; delete it and dimension again to measure something else.")
        #expect(names(s).isEmpty)
        #expect(s.dimension(Scene.horizontal)?.kind == .linear(.horizontal))
    }

    @Test func aDatumBlocksDiameterToRadius() {
        let s = Scene.make([.diameter])
        let datumID = AnnotationID()
        s.h.model.commitSheet("Setup") { sheet in
            sheet.setAnnotation(
                DrawingAnnotation(
                    id: datumID, view: s.view.id,
                    kind: .datumFeature(DatumFeature(letter: "A", attachment: .dimension(Scene.diameter)))))
        }
        s.h.log.commits.removeAll()
        s.h.model.setDimensionKind(.radius, of: Scene.diameter)
        #expect(s.h.model.refusal == DrawingEditorModel.symbolBlocksKindSentence)
        #expect(s.h.model.refusal == "A datum symbol hangs on this diameter, and a radius can't carry one; delete the datum symbol first.")
        #expect(names(s).isEmpty)
        #expect(s.dimension(Scene.diameter)?.kind == .diameter)
        #expect(s.annotation(datumID) != nil)
        s.h.model.commitSheet("Delete") { $0.removeAnnotation(datumID) }
        s.h.log.commits.removeAll()
        s.h.model.setDimensionKind(.radius, of: Scene.diameter)
        #expect(names(s) == ["Change Dimension"])
        #expect(s.dimension(Scene.diameter)?.kind == .radius)
    }

    @Test func aFrameDoesNotBlockDiameterToRadius() {
        let s = Scene.make([.diameter])
        let frameID = AnnotationID()
        let frame = FeatureControlFrame(
            characteristic: .position, rows: [ToleranceRow(zone: .diameter, value: 0.1)], attachment: .dimension(Scene.diameter))
        s.h.model.commitSheet("Setup") { sheet in
            sheet.setAnnotation(DrawingAnnotation(id: frameID, view: s.view.id, kind: .featureControl(frame)))
        }
        s.h.log.commits.removeAll()
        s.h.model.setDimensionKind(.radius, of: Scene.diameter)
        #expect(names(s) == ["Change Dimension"])
        #expect(s.dimension(Scene.diameter)?.kind == .radius)
        guard case .featureControl(let kept)? = s.annotation(frameID)?.kind else {
            Issue.record("the frame is gone")
            return
        }
        #expect(kept.attachment == .dimension(Scene.diameter))
        #expect(s.report[frameID]?.status == .held)
    }
}

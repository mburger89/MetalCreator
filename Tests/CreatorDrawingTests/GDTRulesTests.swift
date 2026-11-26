import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

/// DR-4 Task 4: R8's rules as warnings.
@Suite("GD&T rules")
struct GDTRulesTests {
    let node = NodeID()
    let viewA = ViewID()
    let viewB = ViewID()

    func end() -> LeaderEnd {
        let pick = EdgePick(
            key: EdgeKey([TopoTag(node: node, item: 0, role: .startCap)], [TopoTag(node: node, item: 0, role: .endCap)]),
            matchCount: 1)
        return LeaderEnd(target: .edge(pick), hint: Vector2(3, 4))
    }

    func datum(_ letter: String) -> DrawingAnnotation {
        DrawingAnnotation(view: viewA, kind: .datumFeature(DatumFeature(letter: letter, attachment: .feature(end()))))
    }

    func basic(view: ViewID) -> DrawingAnnotation {
        DrawingAnnotation(
            view: view,
            kind: .dimension(
                DrawingDimension(
                    kind: .linear(.horizontal), anchors: [.point(Vector2(0, 0)), .point(Vector2(10, 0))],
                    placement: DimensionPlacement(offset: 5, angle: 0), tolerance: .basic)))
    }

    func frame(
        _ characteristic: GeometricCharacteristic, rows: [[String]], view: ViewID? = nil
    ) -> DrawingAnnotation {
        let rows = rows.map { ToleranceRow(value: 0.1, datums: $0.map { DatumReference(letter: $0) }) }
        return DrawingAnnotation(
            view: view ?? viewA,
            kind: .featureControl(FeatureControlFrame(characteristic: characteristic, rows: rows, attachment: .feature(end()))))
    }

    func check(
        _ annotation: DrawingAnnotation, others: [DrawingAnnotation] = [], standard: DrawingStandard = .iso,
        extraSheets: [[DrawingAnnotation]] = []
    ) -> [String] {
        var sheet = DrawingSheet(name: "S")
        for item in [annotation] + others { sheet.setAnnotation(item) }
        var sheets = [sheet]
        for annotations in extraSheets {
            var more = DrawingSheet(name: "T")
            for item in annotations { more.setAnnotation(item) }
            sheets.append(more)
        }
        let document = DrawingDocument(settings: DrawingSettings(standard: standard), sheets: sheets)
        return GDTRules.warnings(for: annotation, context: .make(document: document, sheet: sheet))
    }

    @Test func formTakesNoDatum() {
        let result = check(frame(.flatness, rows: [["A"]]), others: [datum("A")])
        #expect(result == ["Flatness is a form tolerance and takes no datum."])
    }

    @Test func orientationNeedsADatum() {
        #expect(check(frame(.perpendicularity, rows: [[]])) == ["Perpendicularity needs a datum reference."])
    }

    @Test func runoutNeedsADatum() {
        #expect(check(frame(.totalRunout, rows: [[]])) == ["Total run-out needs a datum reference."])
    }

    @Test func profileMayGoEitherWay() {
        #expect(check(frame(.surfaceProfile, rows: [[]])).isEmpty)
        #expect(check(frame(.lineProfile, rows: [["A"]]), others: [datum("A")]).isEmpty)
    }

    @Test func positionNeedsABasicDimensionInItsView() {
        let position = frame(.position, rows: [["A"]])
        let a = datum("A")
        #expect(check(position, others: [a]) == [GDTRules.positionNeedsBasic])
        #expect(check(position, others: [a, basic(view: viewB)]) == [GDTRules.positionNeedsBasic])
        #expect(check(position, others: [a, basic(view: viewA)]).isEmpty)
    }

    @Test func duplicateAndUndefinedLetters() {
        let result = check(frame(.surfaceProfile, rows: [["A", "D"], ["A", "D"]]), others: [datum("A")])
        #expect(result == ["Datum D isn't defined: no datum symbol on this drawing has that letter."])
        let one = datum("A")
        let two = datum("A")
        let both = check(one, others: [], extraSheets: [[two]])
        #expect(both == ["Datum A is defined by more than one datum symbol on this drawing."])
        #expect(check(two, extraSheets: [[one]]) == both)
        #expect(check(datum("B")).isEmpty)
    }

    @Test func asmeWarnsAboutConcentricityAndSymmetry() {
        let concentric = frame(.concentricity, rows: [["A"]])
        let symmetric = frame(.symmetry, rows: [["A"]])
        let a = datum("A")
        #expect(check(concentric, others: [a]).isEmpty)
        #expect(check(symmetric, others: [a]).isEmpty)
        #expect(check(concentric, others: [a], standard: .asme) == [GDTRules.asmeConcentricity])
        #expect(check(symmetric, others: [a], standard: .asme) == [GDTRules.asmeSymmetry])
    }

    @Test func compositeLowerDatumsArePrefix() {
        let others = [datum("A"), datum("B")]
        #expect(check(frame(.surfaceProfile, rows: [["A", "B"], ["A"]]), others: others).isEmpty)
        #expect(check(frame(.surfaceProfile, rows: [["A", "B"], ["B"]]), others: others) == [GDTRules.compositeDatums])
    }

    @Test func warningsComeInOrder() {
        // Rule 2 (no datum in the first row), 3 (no basic dimension), 4 (D is undefined).
        let result = check(frame(.position, rows: [[], ["D"]]))
        #expect(
            result == [
                "Position needs a datum reference.", GDTRules.positionNeedsBasic, GDTRules.undefined("D"),
                GDTRules.compositeDatums,
            ])
    }

    @Test func aLostFrameIsStillChecked() {
        var lost = frame(.flatness, rows: [["A"]])
        lost.last = LastGood(values: [0.1], lines: ["0.1"], figure: .centreMark(center: Vector2(0, 0), radius: 1))
        #expect(check(lost, others: [datum("A")]) == [GDTRules.formWithDatum(.flatness)])
    }
}

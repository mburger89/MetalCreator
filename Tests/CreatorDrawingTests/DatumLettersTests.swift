import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Datum letters")
struct DatumLettersTests {
    @Test func datumLetterRules() {
        for valid in ["A", "Z", "AA", "B", "AB"] { #expect(DatumLetters.isValid(valid), "\(valid)") }
        for invalid in ["I", "O", "Q", "AI", "AAA", "1", "", "Ä", "a"] { #expect(!DatumLetters.isValid(invalid), "\(invalid)") }
        #expect(DatumLetters.normalized(" b ") == "B")
        #expect(DatumLetters.normalized("i") == nil)
        #expect(DatumLetters.normalized("Ä") == nil)
        #expect(DatumLetters.normalized("") == nil)
    }

    private func document(_ sheets: [[String]]) -> DrawingDocument {
        let node = NodeID()
        let target = LeaderEnd(target: .point(Vector2(0, 0)), hint: Vector2(0, 0))
        return DrawingDocument(
            sheets: sheets.map { letters in
                let view = DrawingView(kind: .base, source: node, orientation: .standard(.front), center: Vector2(0, 0))
                let annotations = letters.map {
                    DrawingAnnotation(
                        view: view.id, kind: .datumFeature(DatumFeature(letter: $0, attachment: .feature(target))))
                }
                return DrawingSheet(name: "S", views: [view], annotations: annotations)
            })
    }

    @Test func nextLetterSpansTheDocument() {
        #expect(DatumLetters.next(in: document([["A"], ["B"]])) == "C")
        #expect(DatumLetters.next(in: document([["A", "C"]])) == "B")
        #expect(DatumLetters.next(in: document([])) == "A")
        let single = "ABCDEFGHJKLMNPRSTUVWXYZ".map(String.init)
        #expect(DatumLetters.next(in: document([single])) == "AA")
    }

    @Test func lettersFollowSheetsThenAnnotationOrder() {
        let doc = document([["B"], ["A"]])
        #expect(DatumLetters.letters(in: doc) == ["B", "A"])
    }
}

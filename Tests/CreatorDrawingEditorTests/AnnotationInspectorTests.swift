import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The inspector's setters for annotations and the drawing's number settings: each one step, each refusal in words.
@MainActor
@Suite("Annotation inspector")
struct AnnotationInspectorTests {
    private typealias Scene = SelectionScene
    private static let badNumber = "A tolerance is a number, such as 0.1."
    private static let badGeneral = "A general tolerance is a number, such as 0.1."

    private func names(_ s: Scene) -> [String] { s.h.log.commits.map(\.name) }

    /// Rewrites one annotation's kind in place, as undo would bring it back.
    private func rewrite(_ s: Scene, _ id: AnnotationID, _ change: (inout AnnotationKind) -> Void) {
        var document = s.h.model.document
        var annotation = document.sheets[0].annotation(id)!
        change(&annotation.kind)
        document.sheets[0].setAnnotation(annotation)
        s.h.model.replaceDocument(document)
    }

    @Test func kindAndDirection() {
        let s = Scene.make([.horizontal, .diameter])
        let m = s.h.model
        m.setDimensionKind(.linear(.vertical), of: Scene.horizontal)
        #expect(names(s) == ["Change Dimension"])
        #expect(s.dimension(Scene.horizontal)?.kind == .linear(.vertical))
        m.setDimensionKind(.linear(.vertical), of: Scene.horizontal)
        #expect(names(s).count == 1, "no change, no step")
        m.setDimensionKind(.radius, of: Scene.diameter)
        #expect(s.dimension(Scene.diameter)?.kind == .radius)
        m.setDimensionKind(.diameter, of: Scene.diameter)
        #expect(s.dimension(Scene.diameter)?.kind == .diameter)
        m.setDimensionKind(.radius, of: Scene.horizontal)
        #expect(s.dimension(Scene.horizontal)?.kind == .linear(.vertical), "a distance never becomes a radius")
        #expect(names(s).count == 3)
        rewrite(s, Scene.horizontal) { kind in
            if case .dimension(var d) = kind {
                d.kind = .baseline(.horizontal)
                kind = .dimension(d)
            }
        }
        let before = s.h.log.commits.count
        m.setDimensionKind(.baseline(.aligned), of: Scene.horizontal)
        #expect(m.refusal == "Baseline and chain dimensions run horizontally or vertically.")
        m.setDimensionKind(.linear(.aligned), of: Scene.horizontal)
        #expect(m.refusal == "Baseline and chain dimensions run horizontally or vertically.")
        #expect(s.h.log.commits.count == before)
        m.setDimensionKind(.linear(.vertical), of: Scene.horizontal)
        #expect(s.dimension(Scene.horizontal)?.kind == .baseline(.vertical), "a baseline stays a baseline")
    }

    @Test func precision() {
        let s = Scene.make([.horizontal])
        s.h.model.setPrecision(3, of: Scene.horizontal)
        #expect(names(s) == ["Change Dimension"])
        #expect(s.dimension(Scene.horizontal)?.precision == 3)
        s.h.model.setPrecision(3, of: Scene.horizontal)
        s.h.model.setPrecision(nil, of: Scene.horizontal)
        #expect(s.dimension(Scene.horizontal)?.precision == nil)
        #expect(names(s).count == 2)
        s.h.model.setPrecision(9, of: Scene.horizontal)
        #expect(s.h.model.refusal != nil)
        #expect(names(s).count == 2)
    }

    @Test func prefixAndSuffix() {
        let s = Scene.make([.horizontal])
        s.h.model.setPrefix("~", of: Scene.horizontal)
        s.h.model.setSuffix(" REF", of: Scene.horizontal)
        #expect(names(s) == ["Change Dimension", "Change Dimension"])
        #expect(s.dimension(Scene.horizontal)?.prefix == "~")
        #expect(s.dimension(Scene.horizontal)?.suffix == " REF")
    }

    @Test func toleranceKinds() {
        let s = Scene.make([.horizontal, .diameter])
        let m = s.h.model
        let cases: [(DimensionTolerance, AnnotationID)] = [
            (.symmetric(0.1), Scene.horizontal), (.deviation(upper: 0.1, lower: -0.2), Scene.horizontal),
            (.limits(upper: 0.1, lower: -0.1), Scene.horizontal), (.reference, Scene.horizontal), (.basic, Scene.horizontal),
            (.fit(.hole(.H, grade: 7), showsDeviations: true), Scene.diameter), (.general, Scene.horizontal),
        ]
        for (tolerance, id) in cases {
            let before = s.h.log.commits.count
            m.setTolerance(tolerance, of: id)
            #expect(s.h.log.commits.count == before + 1, "\(tolerance)")
            #expect(s.h.log.commits.last?.name == "Change Tolerance")
            #expect(s.dimension(id)?.tolerance == tolerance)
        }
        let before = s.h.log.commits.count
        m.setTolerance(.general, of: Scene.horizontal)
        #expect(s.h.log.commits.count == before)
    }

    @Test func aFitOnARadiusIsRefused() {
        let s = Scene.make([.diameter, .horizontal])
        s.h.model.setDimensionKind(.radius, of: Scene.diameter)
        let before = s.h.log.commits.count
        s.h.model.setTolerance(.fit(.hole(.H, grade: 7), showsDeviations: true), of: Scene.diameter)
        #expect(s.h.model.refusal == "Fits apply to sizes: a diameter or a distance between two faces.")
        #expect(s.h.log.commits.count == before)
        s.h.model.setTolerance(.fit(.shaft(.g, grade: 6), showsDeviations: false), of: Scene.horizontal)
        #expect(s.h.log.commits.count == before + 1, "a linear size takes a fit")
    }

    @Test func aBadToleranceNumberIsRefused() {
        let s = Scene.make([.horizontal])
        let m = s.h.model
        m.setTolerance(symmetricText: "abc", of: Scene.horizontal)
        #expect(m.refusal == Self.badNumber)
        m.setTolerance(symmetricText: "", of: Scene.horizontal)
        #expect(m.refusal == Self.badNumber)
        m.refusal = nil
        m.setTolerance(upperText: "0.1", lowerText: "x", of: Scene.horizontal)
        #expect(m.refusal == Self.badNumber)
        m.refusal = nil
        m.setTolerance(symmetricText: "-0.1", of: Scene.horizontal)
        #expect(m.refusal == Self.badNumber, "a symmetric tolerance is a positive amount")
        #expect(s.h.log.commits.isEmpty)
        m.setTolerance(symmetricText: "0.1", of: Scene.horizontal)
        m.setTolerance(upperText: "+0.1", lowerText: "-0.2", of: Scene.horizontal)
        m.setTolerance(upperText: "0.3", lowerText: "-0.3", limits: true, of: Scene.horizontal)
        #expect(names(s) == ["Change Tolerance", "Change Tolerance", "Change Tolerance"])
        #expect(s.dimension(Scene.horizontal)?.tolerance == .limits(upper: 0.3, lower: -0.3))
    }

    @Test func tolerancesAreTypedInTheDocumentUnit() {
        let s = Scene.make([.horizontal], units: DocumentUnits(length: .inches))
        s.h.model.setTolerance(symmetricText: "0.005", of: Scene.horizontal)
        guard case .symmetric(let value)? = s.dimension(Scene.horizontal)?.tolerance else {
            Issue.record("not symmetric")
            return
        }
        #expect(abs(value - 0.127) < 1e-9)
    }

    @Test func anAngleToleranceIsTypedInDegrees() {
        let s = Scene.make([.horizontal])
        rewrite(s, Scene.horizontal) { kind in
            if case .dimension(var d) = kind {
                d.kind = .angle
                kind = .dimension(d)
            }
        }
        s.h.model.setTolerance(symmetricText: "90", of: Scene.horizontal)
        guard case .symmetric(let value)? = s.dimension(Scene.horizontal)?.tolerance else {
            Issue.record("not symmetric")
            return
        }
        #expect(abs(value - .pi / 2) < 1e-12)
    }

    @Test func anEmptyNoteIsRefused() {
        let s = Scene.make([.note])
        s.h.model.setNoteText("   ", of: Scene.note)
        #expect(s.h.model.refusal == "A note can't be empty.")
        #expect(s.h.log.commits.isEmpty)
        s.h.model.setNoteText("Plate", of: Scene.note)
        #expect(s.h.log.commits.isEmpty, "the same text")
        s.h.model.setNoteText("Break edges\nDeburr", of: Scene.note)
        #expect(names(s) == ["Edit Note"])
        #expect(s.note(Scene.note)?.text == "Break edges\nDeburr")
    }

    @Test func removeLeader() {
        let s = Scene.make([.note])
        rewrite(s, Scene.note) { kind in
            if case .note(var note) = kind {
                note.leaders = [
                    LeaderEnd(target: .point(Vector2(1, 1)), hint: .zero), LeaderEnd(target: .point(Vector2(2, 2)), hint: .zero),
                ]
                kind = .note(note)
            }
        }
        s.h.model.removeLeader(at: 5, of: Scene.note)
        #expect(s.h.log.commits.isEmpty)
        s.h.model.removeLeader(at: 0, of: Scene.note)
        #expect(names(s) == ["Remove Leader"])
        #expect(s.note(Scene.note)?.leaders.map(\.target) == [.point(Vector2(2, 2))])
    }

    @Test func centreMarksToggleIsChangeView() {
        let s = Scene.make([.mark])
        s.h.model.setShowsCentreMarks(false, of: s.view.id)
        #expect(names(s) == ["Change View"])
        #expect(s.h.model.document.sheets[0].view(s.view.id)?.showsCentreMarks == false)
        s.h.model.setShowsCentreMarks(false, of: s.view.id)
        #expect(names(s).count == 1)
    }

    @Test func generalToleranceIsEditTitleBlock() {
        let s = Scene.make([])
        s.h.model.setGeneralTolerance(.iso2768(.f, nil))
        #expect(names(s) == ["Edit Title Block"])
        #expect(s.h.model.document.settings.generalTolerance == .iso2768(.f, nil))
        s.h.model.setGeneralTolerance(.iso2768(.f, nil))
        #expect(names(s).count == 1)
    }

    @Test func decimalSignIsChangeNumberFormat() {
        let s = Scene.make([])
        s.h.model.setDecimalSign(.comma)
        #expect(names(s) == ["Change Number Format"])
        #expect(s.h.model.document.settings.decimalSign == .comma)
        s.h.model.setDecimalSign(.comma)
        #expect(names(s).count == 1)
    }

    @Test func asmeRowsStoreTheMagnitude() {
        let s = Scene.make([])
        s.h.model.setGeneralTolerance(.asme(.inches))
        s.h.model.setASMEToleranceRow(places: 3, text: " .010 ")
        #expect(names(s) == ["Edit Title Block", "Edit Title Block"])
        guard case .asme(let table) = s.h.model.document.settings.generalTolerance else {
            Issue.record("not a table")
            return
        }
        #expect(table.rows.first { $0.places == 3 }?.text == ".010")
        #expect(s.h.model.document.settings.generalTolerance.text.contains("±.010"))
        s.h.model.setASMEToleranceRow(places: 4, text: "0.0005")
        guard case .asme(let grown) = s.h.model.document.settings.generalTolerance else { return }
        #expect(grown.rows.map(\.places) == [1, 2, 3, 4], "a new row is added in order")
    }

    @Test func aBadASMERowIsRefused() {
        let s = Scene.make([])
        s.h.model.setGeneralTolerance(.asme(.millimetres))
        let before = s.h.log.commits.count
        for text in ["±0.5", "abc", "0", "-1", ""] {
            s.h.model.refusal = nil
            s.h.model.setASMEToleranceRow(places: 1, text: text)
            #expect(s.h.model.refusal == Self.badGeneral, "\(text)")
        }
        #expect(s.h.log.commits.count == before)
        s.h.model.setGeneralTolerance(.asme(ASMEToleranceTable(unit: .millimetres, rows: [ASMEToleranceRow(places: 0, text: "x")])))
        #expect(s.h.model.refusal == Self.badGeneral)
        #expect(s.h.log.commits.count == before)
    }

    @Test func aRowNeedsATable() {
        let s = Scene.make([])
        s.h.model.setGeneralTolerance(.iso2768(.m, .K))
        let before = s.h.log.commits.count
        s.h.model.setASMEToleranceRow(places: 1, text: "0.1")
        #expect(s.h.log.commits.count == before)
    }

    @Test func lostAnnotationsListed() throws {
        let held = Scene.make([.horizontal, .note])
        #expect(held.h.model.lostAnnotations.isEmpty)
        let s = Scene.make([.horizontal, .note], removing: [103])
        let lost = try #require(s.h.model.lostAnnotations.first)
        #expect(s.h.model.lostAnnotations.count == 1)
        #expect(lost.id == Scene.horizontal)
        #expect(lost.label.hasSuffix("?"))
        #expect(lost.reason == LostReason.missing.sentence)
    }
}

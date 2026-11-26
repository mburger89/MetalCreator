import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

struct ViewDerivationTests {
    private func id(_ n: Int) -> ViewID {
        ViewID(rawValue: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n)) ?? UUID())
    }

    private let node = NodeID()
    private let frame = StandardOrientation.top.frame

    private var cutter: SectionCutter {
        SectionCutter(frame: frame, points: [Vector2(0, 0), Vector2(20, 0)], viewing: Vector2(0, 1))
    }

    private func base(_ n: Int, _ orientation: ViewOrientation = .standard(.front)) -> DrawingView {
        DrawingView(id: id(n), kind: .base, source: node, orientation: orientation, center: .zero)
    }

    private func section(
        _ n: Int, parent: ViewID, orientation: ViewOrientation? = nil, cutter given: SectionCutter? = nil
    ) -> DrawingView {
        let used = given ?? cutter
        return DrawingView(
            id: id(n), kind: .section, source: node,
            orientation: orientation ?? .custom(SectionFrame.frame(for: used)), center: .zero,
            derivation: .section(SectionLine(parent: parent, cutter: used)), letter: "A")
    }

    private func detail(_ n: Int, parent: ViewID, orientation: ViewOrientation = .standard(.front)) -> DrawingView {
        DrawingView(
            id: id(n), kind: .detail, source: node, orientation: orientation, center: .zero,
            derivation: .detail(DetailCircle(parent: parent, center: .zero, radius: 3)), letter: "B")
    }

    private func roundTrip(_ sheet: DrawingSheet) throws -> DrawingSheet {
        try JSONDecoder().decode(DrawingSheet.self, from: JSONEncoder().encode(sheet))
    }

    @Test func everyCaseRoundTripsByType() throws {
        let cases: [ViewDerivation] = [
            .section(SectionLine(parent: id(1), cutter: cutter)),
            .detail(DetailCircle(parent: id(1), center: Vector2(1, 2), radius: 3)),
            .auxiliary(AuxiliaryArrow(parent: id(1), parentFrame: frame, at: Vector2(1, 1), viewing: Vector2(0, 1))),
        ]
        for derivation in cases {
            let data = try JSONEncoder().encode(derivation)
            let text = try #require(String(bytes: data, encoding: .utf8))
            #expect(text.contains("\"type\""))
            #expect(!text.contains("_0"))
            #expect(try JSONDecoder().decode(ViewDerivation.self, from: data) == derivation)
            #expect(derivation.parent == id(1))
            #expect(derivation.withParent(id(2)).parent == id(2))
        }
    }

    @Test func aDerivedViewWithoutItsDataIsDropped() throws {
        var bare = section(2, parent: id(1))
        bare.derivation = nil
        var wrong = detail(3, parent: id(1))
        wrong.kind = .auxiliary
        var sheet = DrawingSheet(name: "S", views: [base(1), bare, wrong])
        sheet.setAnnotation(DrawingAnnotation(id: AnnotationID(), view: bare.id, kind: .note(DrawingNote(text: "n", position: .zero))))
        let back = try roundTrip(sheet)
        #expect(back.views.map(\.id) == [id(1)])
        #expect(back.annotations.isEmpty)
    }

    @Test func aBaseViewDropsAStrayDerivation() throws {
        var stray = base(1)
        stray.derivation = .detail(DetailCircle(parent: id(9), center: .zero, radius: 1))
        let back = try roundTrip(DrawingSheet(name: "S", views: [stray]))
        #expect(back.views.count == 1)
        #expect(back.views[0].derivation == nil)
    }

    @Test func aSectionsOrientationIsRepaired() throws {
        let wrong = section(2, parent: id(1), orientation: .standard(.right))
        let back = try roundTrip(DrawingSheet(name: "S", views: [base(1), wrong]))
        #expect(back.views[1].orientation == .custom(SectionFrame.frame(for: cutter)))
    }

    @Test func isPictorialRule() {
        let iso = base(1, .standard(.isometricFrontRight))
        let isoDetail = detail(2, parent: id(1), orientation: iso.orientation)
        let front = base(3)
        let sect = section(4, parent: id(3))
        let slant = ProjectionFrame(direction: Vector3(0.6, 0.8, 0), up: Vector3(0, 0, 1))
        let aux = DrawingView(
            id: id(5), kind: .auxiliary, source: node, orientation: .custom(slant), center: .zero,
            derivation: .auxiliary(AuxiliaryArrow(parent: id(3), parentFrame: frame, at: .zero, viewing: Vector2(0, 1))),
            letter: "C")
        let auxDetail = detail(6, parent: id(5), orientation: .custom(slant))
        let slantedCutter = SectionCutter(frame: frame, points: [Vector2(0, 0), Vector2(10, 5)], viewing: Vector2(-5, 10))
        let slantedSection = section(7, parent: id(3), cutter: slantedCutter)
        let slantedDetail = detail(8, parent: id(7), orientation: .custom(slant))
        let detailOfDetail = detail(9, parent: id(8), orientation: .custom(slant))
        let orphanSlanted = detail(10, parent: id(99), orientation: .custom(slant))
        let orphanFront = detail(11, parent: id(99))
        let sheet = DrawingSheet(
            name: "S",
            views: [
                iso, isoDetail, front, sect, aux, auxDetail, slantedSection, slantedDetail, detailOfDetail, orphanSlanted,
                orphanFront,
            ])
        #expect(sheet.isPictorial(iso))
        #expect(sheet.isPictorial(isoDetail))
        #expect(!sheet.isPictorial(front))
        #expect(!sheet.isPictorial(sect))
        #expect(!sheet.isPictorial(aux))
        #expect(!sheet.isPictorial(auxDetail))
        #expect(!sheet.isPictorial(slantedSection))
        #expect(!sheet.isPictorial(slantedDetail))
        #expect(!sheet.isPictorial(detailOfDetail))
        #expect(sheet.isPictorial(orphanSlanted))
        #expect(!sheet.isPictorial(orphanFront))
    }

    @Test func derivationCyclesAreBroken() throws {
        let selfParent = detail(1, parent: id(1))
        let a = detail(2, parent: id(3))
        let b = detail(3, parent: id(2))
        let c = detail(4, parent: id(5))
        let d = detail(5, parent: id(90))
        let orphanSection = section(6, parent: id(91))
        var sheet = DrawingSheet(name: "S", views: [selfParent, a, b, c, d, orphanSection])
        let note = DrawingNote(text: "n", position: .zero)
        sheet.setAnnotation(DrawingAnnotation(id: AnnotationID(), view: selfParent.id, kind: .note(note)))
        let back = try roundTrip(sheet)
        #expect(back.views.map(\.id) == [id(3), id(4), id(5), id(6)])
        #expect(back.view(id(3))?.derivation?.parent == id(2))
        #expect(back.annotations.isEmpty)
    }

    @Test func twoDerivedViewsSharingAnIdDoNotCrashTheDecoder() throws {
        let first = detail(2, parent: id(1))
        var second = detail(2, parent: id(1))
        second.letter = "C"
        let back = try roundTrip(DrawingSheet(name: "S", views: [base(1), first, second]))
        #expect(back.views.contains { $0.id == id(1) })
        #expect(back.view(id(2)) != nil)
    }
}

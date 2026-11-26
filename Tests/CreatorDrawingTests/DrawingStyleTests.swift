import Testing

@testable import CreatorDrawing

@Suite("Drawing style")
struct DrawingStyleTests {
    @Test func styleConstants() {
        let iso = DrawingStyle.iso
        #expect(iso.thick == 0.5 && iso.thin == 0.25 && iso.frame == 0.7 && iso.zone == 0.35)
        #expect(iso.hiddenDash == 3 && iso.hiddenGap == 1.5)
        #expect(iso.notesHeight(for: .a3) == 2.5 && iso.notesHeight(for: .a4) == 2.5)
        #expect(iso.notesHeight(for: .a1) == 3.5 && iso.notesHeight(for: .ansiD) == 3.5)
        #expect(iso.titleHeight == 7 && iso.viewLabelHeight == 5)
        #expect(iso.fieldLabelHeight == 1.8 && iso.zoneLabelHeight == 3.5)
        let asme = DrawingStyle.asme
        #expect(asme.thick == 0.6 && asme.thin == 0.3)
        #expect(asme.notesHeight(for: .ansiB) == 3 && asme.notesHeight(for: .ansiE) == 3)
        #expect(asme.titleHeight == 6 && asme.viewLabelHeight == 6)
        #expect(DrawingStyle.of(.iso) == iso && DrawingStyle.of(.asme) == asme)
    }

    @Test func eachStandardsDashesArePinnedByValue() {
        // ISO and ASME draw hidden lines alike (3 mm dash, 1.5 mm gap); the chain lines are each the standard's own.
        for style in [DrawingStyle.iso, .asme] { #expect(style.hiddenDash == 3 && style.hiddenGap == 1.5) }
        #expect(DrawingStyle.iso.centreDash == [6, 0.75, 0.25, 0.75])
        #expect(DrawingStyle.asme.centreDash == [19, 1.5, 3, 1.5])
    }

    @Test func hatchSpacingBySize() {
        for style in [DrawingStyle.iso, .asme] {
            #expect(style.hatchSpacing(for: .a4) == 2.5 && style.hatchSpacing(for: .ansiA) == 2.5)
            #expect(style.hatchSpacing(for: .a2) == 4 && style.hatchSpacing(for: .ansiD) == 4)
        }
    }
}

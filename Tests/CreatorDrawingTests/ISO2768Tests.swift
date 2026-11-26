import Testing

@testable import CreatorDrawing

struct ISO2768Tests {
    @Test func mediumAt25() { #expect(ISO2768.linear(25, class: .m) == 0.2) }

    @Test func mediumAt30() {
        #expect(ISO2768.linear(30, class: .m) == 0.2)
        #expect(ISO2768.linear(30.001, class: .m) == 0.3)
    }

    @Test func underHalfAMillimetreHasNone() {
        #expect(ISO2768.linear(0.4, class: .m) == nil)
        #expect(ISO2768.brokenEdge(0.4, class: .m) == nil)
    }

    @Test func veryCoarseBelowThreeHasNone() { #expect(ISO2768.linear(2, class: .v) == nil) }
    @Test func fineAbove2000HasNone() { #expect(ISO2768.linear(3000, class: .f) == nil) }
    @Test func over4000HasNone() { #expect(ISO2768.linear(4000.1, class: .c) == nil) }

    @Test func brokenEdges() {
        #expect(ISO2768.brokenEdge(2, class: .m) == 0.2)
        #expect(ISO2768.brokenEdge(5, class: .c) == 1)
        #expect(ISO2768.brokenEdge(10, class: .f) == 1)
    }

    @Test func asmeRowsByPlaces() throws {
        let mm = GeneralTolerance.asme(.millimetres)
        #expect(mm.value(for: 10, use: .length, places: 1) == 0.1)
        let inches = GeneralTolerance.asme(.inches)
        #expect(try abs(#require(inches.value(for: 1, use: .length, places: 2)) - 0.254) < 1e-12)
        #expect(inches.value(for: 1, use: .length, places: 5) == nil)
    }

    @Test func isoValuesThroughTheTolerance() {
        let tolerance = GeneralTolerance.iso2768(.m, .K)
        #expect(tolerance.value(for: 25, use: .length, places: 0) == 0.2)
        #expect(tolerance.value(for: 25, use: .brokenEdge, places: 0) == 1)
        #expect(tolerance.value(for: 25, use: .angle, places: 0) == nil)
        #expect(GeneralTolerance.text("x").value(for: 25, use: .length, places: 0) == nil)
    }

    @Test func summaries() {
        let iso = GeneralTolerance.iso2768(.m, .K)
        #expect(iso.summary(for: 25, use: .length, places: 0) == "±0.2 (ISO 2768-m)")
        #expect(iso.summary(for: 100, use: .angle, places: 0) == "ISO 2768-m")
        #expect(iso.summary(for: 2000.5, use: .length, places: 0) == "±2 (ISO 2768-m)")
        #expect(GeneralTolerance.asme(.millimetres).summary(for: 5, use: .length, places: 1) == "±0.1")
        #expect(GeneralTolerance.text("x").summary(for: 5, use: .length, places: 1) == nil)
    }
}

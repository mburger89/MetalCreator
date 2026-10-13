import CreatorStyle
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The ramp's range rules (fields spec §6, "Ramp and legend").
struct FieldPreviewRangeTests {
    func make(_ low: Double, _ high: Double, signed: Bool = false, unit: Bool = false) -> FieldPreviewRange? {
        FieldPreviewRange.make(extent: low...high, centredOnZero: signed, fixedToUnit: unit)
    }

    @Test func automaticIsTheSampledMinimumToMaximumWithTheMiddleHalfway() {
        #expect(make(2, 10) == FieldPreviewRange(low: 2, mid: 6, high: 10))
        #expect(make(-3, 1) == FieldPreviewRange(low: -3, mid: -1, high: 1))
    }

    @Test func aSignedDistanceCentresTheMiddleOnZeroAndIsSymmetric() {
        #expect(make(-4, 10, signed: true) == FieldPreviewRange(low: -10, mid: 0, high: 10))
        #expect(make(-12, 3, signed: true) == FieldPreviewRange(low: -12, mid: 0, high: 12))
        #expect(make(2, 6, signed: true) == FieldPreviewRange(low: -6, mid: 0, high: 6), "all outside the part: still centred")
        #expect(make(0, 0, signed: true) == FieldPreviewRange(low: -1, mid: 0, high: 1))
    }

    @Test func theUnitToggleFixesTheRangeWhateverWasSampled() {
        #expect(make(-50, 50, unit: true) == .unit && make(-50, 50, signed: true, unit: true) == .unit)
        #expect(FieldPreviewRange.make(extent: nil, centredOnZero: false, fixedToUnit: true) == .unit, "even with nothing sampled")
        #expect(FieldPreviewRange.unit == FieldPreviewRange(low: 0, mid: 0.5, high: 1))
    }

    @Test func aFieldThatIsTheSameEverywhereGetsAUnitWideRange() {
        #expect(make(3, 3) == FieldPreviewRange(low: 2.5, mid: 3, high: 3.5))
    }

    @Test func noFiniteValueGivesNoRangeUnlessItIsFixed() {
        #expect(FieldPreviewRange.make(extent: nil, centredOnZero: false, fixedToUnit: false) == nil)
    }

    @Test func theRampTakesTheThemesThreeRolesAndTheRange() {
        let range = FieldPreviewRange(low: -2, mid: 0, high: 6)
        let ramp = range.ramp(colors: ColorTheme.dracula.colors)
        #expect(ramp.low == ColorTheme.dracula.colors.fieldLow.rgba && ramp.mid == ColorTheme.dracula.colors.fieldMid.rgba)
        #expect(ramp.high == ColorTheme.dracula.colors.fieldHigh.rgba)
        #expect(ramp.lowValue == -2 && ramp.midValue == 0 && ramp.highValue == 6)
    }
}

import Testing
@testable import CreatorViewport

/// The ramp a field is drawn in (fields spec §6): three colours at three values, straight blends between, held beyond.
struct FieldRampTests {
    static let red = SIMD4<Float>(1, 0, 0, 1)
    static let green = SIMD4<Float>(0, 1, 0, 1)
    static let blue = SIMD4<Float>(0, 0, 1, 1)
    let ramp = FieldRamp(low: red, mid: green, high: blue, lowValue: -2, midValue: 0, highValue: 4)

    @Test func theStopsAreTheirColours() {
        #expect(ramp.color(at: -2) == Self.red && ramp.color(at: 0) == Self.green && ramp.color(at: 4) == Self.blue)
    }

    @Test func betweenTheStopsItBlendsInAStraightLine() {
        #expect(ramp.color(at: -1) == SIMD4<Float>(0.5, 0.5, 0, 1))
        #expect(ramp.color(at: 2) == SIMD4<Float>(0, 0.5, 0.5, 1))
    }

    @Test func beyondTheEndsItIsHeld() {
        #expect(ramp.color(at: -50) == Self.red && ramp.color(at: 50) == Self.blue)
    }

    @Test func aRangeInitialiserPutsTheMiddleStopInTheMiddle() {
        let centred = FieldRamp(low: Self.red, mid: Self.green, high: Self.blue, range: 2...10)
        #expect(centred.lowValue == 2 && centred.midValue == 6 && centred.highValue == 10)
        #expect(centred.color(at: 6) == Self.green)
    }

    @Test func stopsAtOneValueDoNotDivideByZero() {
        let flat = FieldRamp(low: Self.red, mid: Self.green, high: Self.blue, lowValue: 3, midValue: 3, highValue: 3)
        #expect(flat.color(at: 3) == Self.green && flat.color(at: 1) == Self.green && flat.color(at: 9) == Self.blue)
    }

    @Test func aValueThatIsNotANumberTakesTheMiddleColour() {
        #expect(ramp.color(at: .nan) == Self.green && ramp.color(at: .infinity) == Self.green)
    }
}

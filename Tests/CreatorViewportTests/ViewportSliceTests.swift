import CreatorGeometry
import Testing
@testable import CreatorViewport

/// The slice a host asks the viewport to draw (fields spec §6): a quad and a grid of values, equal by its `generation`.
@MainActor
struct ViewportSliceTests {
    static let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: 0...1)

    func slice(columns: Int = 2, rows: Int = 2, values: [Float]? = nil, generation: Int = 1,
               origin: Vector3 = Vector3(100, 0, 0)) -> ViewportSlice {
        ViewportSlice(origin: origin, xAxis: .unitX, yAxis: .unitZ, halfWidth: 10, halfHeight: 4, columns: columns, rows: rows,
                      values: values ?? [Float](repeating: 0.5, count: columns * rows), ramp: Self.ramp, generation: generation)
    }

    @Test func theGridSamplesAreTheCentresOfTheTexelsRowByRow() {
        let points = slice().samplePoints()
        #expect(points == [Vector3(95, 0, -2), Vector3(105, 0, -2), Vector3(95, 0, 2), Vector3(105, 0, 2)])
        #expect(slice(columns: 4, rows: 1).samplePoints().map(\.x) == [92.5, 97.5, 102.5, 107.5])
    }

    @Test func aSliceIsValidWhenItHoldsOneValuePerSample() {
        #expect(slice().isValid)
        #expect(!slice(values: [1, 2, 3]).isValid)
        #expect(!slice(columns: 0, rows: 0, values: []).isValid)
        #expect(slice().opacity == 0.85)
    }

    @Test func equalityAndHashingUseTheGenerationNotTheValues() {
        let a = slice(values: [0, 0, 0, 0], generation: 7)
        let b = slice(values: [1, 1, 1, 1], generation: 7)
        #expect(a == b && a.hashValue == b.hashValue, "same generation: the same slice, whatever the values")
        #expect(a != slice(values: [0, 0, 0, 0], generation: 8))
        #expect(a != slice(generation: 7, origin: Vector3(100, 1, 0)))
        var wider = a
        wider.halfWidth = 11
        #expect(wider != a)
    }
}

/// How a slice's numbers are stored in the GPU texture, on every platform (the Metal renderer's `SliceTextures` and the SDL one's
/// `SDLSliceTextures` fill their texels from it): a NaN becomes the ramp's middle value, an infinity the ramp's end it lies beyond.
struct SliceTextureValuesTests {
    @Test func notANumberIsTheMiddleAndInfinityIsTheEndItLiesBeyond() {
        let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: 0...10)
        #expect(SliceTextureValues.filled(.nan, ramp: ramp) == 5)
        #expect(SliceTextureValues.filled(.infinity, ramp: ramp) == 10)
        #expect(SliceTextureValues.filled(-.infinity, ramp: ramp) == 0)
        #expect(SliceTextureValues.filled(3.5, ramp: ramp) == 3.5)
    }
}

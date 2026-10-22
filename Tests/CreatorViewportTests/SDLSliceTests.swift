#if canImport(MetalUISDLGPU)
import CreatorGeometry
import Testing
@testable import CreatorViewport

/// The field slice on SDL_GPU (fields spec §6), as `ViewportSliceRenderTests` reads it on Metal: a translucent quad over the scene,
/// its grid an `r32Float` texture read with a bilinear blend done in the shader. `RenderFixtures`' front view (orthographic, 5 points
/// per mm, centred on (0, 0, 15)) puts a 20 × 20 mm quad in the XZ plane at view x 50…150, y 50…150.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLSliceTests {
    typealias Rig = SDLRenderRig
    /// Red at the quad's left edge, green in the middle, blue at its right edge.
    static let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -1...1)

    /// A 64 × 64 grid whose value grows from −1 on the left to 1 on the right.
    func slice(generation: Int = 1, flipped: Bool = false) -> ViewportSlice {
        let row = (0..<64).map { Float($0) / 63 * 2 - 1 }
        let values = (0..<64).flatMap { _ in flipped ? row.reversed() : row }
        return ViewportSlice(origin: Vector3(0, 0, 15), xAxis: .unitX, yAxis: .unitZ, halfWidth: 10, halfHeight: 10, columns: 64,
                             rows: 64, values: values, ramp: Self.ramp, generation: generation)
    }

    func frame(_ slice: ViewportSlice?) -> ViewportFrame {
        var frame = RenderFixtures.emptyFrame()
        frame.slice = slice
        return frame
    }

    @Test func theQuadShowsTheRampLeftToRightAndLeavesTheRestAlone() async throws {
        let rig = try Rig()
        let with = try await rig.draw(frame(slice()))
        let without = try await rig.draw(frame(nil))
        let left = Rig.color(with, 55, 100), middle = Rig.color(with, 100, 100), right = Rig.color(with, 145, 100)
        #expect(left[0] > 180 && left[1] < 90 && left[2] < 90, "red: \(left)")
        #expect(middle[1] > 180 && middle[0] < 90 && middle[2] < 90, "green: \(middle)")
        #expect(right[2] > 180 && right[0] < 90 && right[1] < 90, "blue: \(right)")
        #expect(Rig.color(with, 30, 100) == Rig.color(without, 30, 100) && Rig.color(with, 100, 30) == Rig.color(without, 100, 30),
                "outside the quad")
        #expect(Rig.color(with, 100, 100) != Rig.color(without, 100, 100))
    }

    @Test func theQuadIsTranslucentSoWhatIsBehindItShowsThrough() async throws {
        let rig = try Rig()
        let without = try await rig.draw(frame(nil))
        let with = try await rig.draw(frame(slice()))
        // The background is a dark gradient (#3a3d4e to #191a21); at 0.85 opacity a fraction of it remains, so the pure green of the
        // ramp's middle is dimmed in red and blue by the background rather than being exactly 0.
        let behind = Rig.color(without, 100, 100), over = Rig.color(with, 100, 100)
        #expect(over[0] > 0 && over[0] <= behind[0] / 2, "some of the background's red remains: \(over) over \(behind)")
    }

    @Test func theValuesAreDrawnWhicheverWayTheyRun() async throws {
        let flipped = try await Rig().draw(frame(slice(generation: 2, flipped: true)))
        let left = Rig.color(flipped, 55, 100), right = Rig.color(flipped, 145, 100)
        #expect(left[2] > 180 && right[0] > 180, "blue on the left now, red on the right: \(left) \(right)")
    }

    @Test func rowZeroIsTheEdgeOnTheNegativeYAxisSide() async throws {
        // Value −1 in row 0 and 1 in the last row: red at the bottom (the −Z edge) and blue at the top.
        let values = (0..<64).flatMap { row in [Float](repeating: Float(row) / 63 * 2 - 1, count: 64) }
        var vertical = slice()
        vertical.values = values
        let bytes = try await Rig().draw(frame(vertical))
        let top = Rig.color(bytes, 100, 55), bottom = Rig.color(bytes, 100, 145)
        #expect(top[2] > 180 && bottom[0] > 180, "the last row is the +Z edge, drawn on top: \(top) \(bottom)")
    }

    @Test func theTextureIsKeptWhileTheGenerationDoesNotChange() async throws {
        let rig = try Rig()
        try await rig.draw(frame(slice(generation: 1)))
        try await rig.draw(frame(slice(generation: 1)))
        #expect(rig.renderer.sliceTextures.uploads == 1)
        try await rig.draw(frame(slice(generation: 2)))
        #expect(rig.renderer.sliceTextures.uploads == 2)
    }

    @Test func anInvalidSliceDrawsNothing() async throws {
        let rig = try Rig()
        var broken = slice()
        broken.values = [0, 1]
        #expect(try await rig.draw(frame(broken)) == (try await rig.draw(frame(nil))))
    }

    @Test func valuesThatAreNotNumbersDrawTheMiddleColour() async throws {
        var nothing = slice()
        nothing.values = [Float](repeating: .nan, count: 64 * 64)
        let middle = Rig.color(try await Rig().draw(frame(nothing)), 55, 100)
        #expect(middle[1] > 180 && middle[0] < 90, "green everywhere: \(middle)")
    }

    @Test func aSliceIsNeverUnderAPick() async throws {
        let rig = try Rig()
        var with = RenderFixtures.boxFrame()
        with.slice = slice()
        let points = stride(from: 20.0, to: 180.0, by: 20.0).flatMap { x in
            stride(from: 20.0, to: 180.0, by: 20.0).map { ScreenPoint(x, $0) }
        }
        let withSlice = try await rig.picks(at: points, in: with)
        let without = try await rig.picks(at: points, in: RenderFixtures.boxFrame())
        #expect(withSlice == without, "the slice is no part of the scene")
        #expect(withSlice.contains { $0 != nil }, "the part itself is still picked")
    }
}
#endif

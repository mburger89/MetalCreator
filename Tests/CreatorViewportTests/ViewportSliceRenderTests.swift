#if canImport(Metal)
import CreatorGeometry
import CreatorKernel
import Metal
import Testing
@testable import CreatorViewport

/// The slice is drawn over the scene as a translucent quad, and the viewport model carries it (fields spec §6). The front view
/// of `OffscreenRenderTests` (orthographic, 5 points per mm, centred on (0, 0, 15)) puts a 20 × 20 mm quad in the XZ plane at
/// view x 50…150, y 50…150.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct ViewportSliceRenderTests {
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
        var frame = ViewportFrame(pose: OffscreenRenderTests.front, size: OffscreenRenderTests.size, sceneBounds: nil, items: [],
                                  shading: .shadedEdges, gridSpacing: 10, handles: [], cube: ViewCubeLayout(),
                                  hoveredCubeRegion: nil, triad: TriadLayout())
        frame.slice = slice
        return frame
    }

    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    @Test func theQuadShowsTheRampLeftToRightAndLeavesTheRestAlone() throws {
        let rig = try RendererCacheTests.Rig()
        let with = try rig.draw(frame(slice()))
        let without = try rig.draw(frame(nil))
        let left = color(with, 55, 100), middle = color(with, 100, 100), right = color(with, 145, 100)
        #expect(left[0] > 180 && left[1] < 90 && left[2] < 90, "red: \(left)")
        #expect(middle[1] > 180 && middle[0] < 90 && middle[2] < 90, "green: \(middle)")
        #expect(right[2] > 180 && right[0] < 90 && right[1] < 90, "blue: \(right)")
        #expect(color(with, 30, 100) == color(without, 30, 100) && color(with, 100, 30) == color(without, 100, 30), "outside the quad")
        #expect(color(with, 100, 100) != color(without, 100, 100))
    }

    @Test func theQuadIsTranslucentSoWhatIsBehindItShowsThrough() throws {
        let rig = try RendererCacheTests.Rig()
        let without = try rig.draw(frame(nil))
        let with = try rig.draw(frame(slice()))
        // The background is a dark gradient (#3a3d4e to #191a21); at 0.85 opacity a fraction of it remains, so the pure green
        // of the ramp's middle is dimmed in red and blue by the background rather than being exactly 0.
        let behind = color(without, 100, 100), over = color(with, 100, 100)
        #expect(over[0] > 0 && over[0] <= behind[0] / 2, "some of the background's red remains: \(over) over \(behind)")
    }

    @Test func theValuesAreDrawnWhicheverWayTheyRun() throws {
        let rig = try RendererCacheTests.Rig()
        let flipped = try rig.draw(frame(slice(generation: 2, flipped: true)))
        let left = color(flipped, 55, 100), right = color(flipped, 145, 100)
        #expect(left[2] > 180 && right[0] > 180, "blue on the left now, red on the right: \(left) \(right)")
    }

    @Test func theTextureIsKeptWhileTheGenerationDoesNotChange() throws {
        let rig = try RendererCacheTests.Rig()
        _ = try rig.draw(frame(slice(generation: 1)))
        _ = try rig.draw(frame(slice(generation: 1)))
        #expect(rig.renderer.sliceTextures.uploads == 1)
        _ = try rig.draw(frame(slice(generation: 2)))
        #expect(rig.renderer.sliceTextures.uploads == 2)
    }

    @Test func anInvalidSliceDrawsNothing() throws {
        let rig = try RendererCacheTests.Rig()
        var broken = slice()
        broken.values = [0, 1]
        #expect(try rig.draw(frame(broken)) == rig.draw(frame(nil)))
    }

    @Test func valuesThatAreNotNumbersDrawTheMiddleColour() throws {
        var nothing = slice()
        nothing.values = [Float](repeating: .nan, count: 64 * 64)
        let bytes = try RendererCacheTests.Rig().draw(frame(nothing))
        let middle = color(bytes, 55, 100)
        #expect(middle[1] > 180 && middle[0] < 90, "green everywhere: \(middle)")
    }

    @Test func aRangeChangeWithoutANewGenerationRefillsTheNonNumbersAndInfinitiesGoToTheEnds() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let textures = SliceTextures()
        var odd = slice()
        odd.values = [Float](repeating: 0, count: 64 * 64)
        (odd.values[0], odd.values[1], odd.values[2]) = (.nan, .infinity, -.infinity)
        func stored(_ slice: ViewportSlice) throws -> [Float] {
            let texture = try #require(textures.texture(for: slice, device: device))
            var out = [Float](repeating: 0, count: 3)
            texture.getBytes(&out, bytesPerRow: 64 * 4, from: MTLRegionMake2D(0, 0, 3, 1), mipmapLevel: 0)
            return out
        }
        #expect(try stored(odd) == [0, 1, -1], "the middle of -1…1, then the ends")
        _ = try stored(odd)
        #expect(textures.uploads == 1)
        odd.ramp = FieldRamp(low: odd.ramp.low, mid: odd.ramp.mid, high: odd.ramp.high, range: 0...10)
        #expect(try stored(odd) == [5, 10, 0], "same generation, new range: filled again")
        #expect(textures.uploads == 2)
    }

    @Test func theModelCarriesTheSliceIntoTheFrameAndTheRenderKey() {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        #expect(model.slice == nil && model.frame(at: 0).slice == nil)
        let key = model.renderKey
        model.showSlice(slice(generation: 1))
        #expect(model.frame(at: 0).slice?.generation == 1)
        #expect(model.renderKey != key, "a new slice redraws")
        let shown = model.renderKey
        model.showSlice(slice(generation: 1))
        #expect(model.renderKey == shown, "an equal slice changes nothing")
        let before = model.slice?.values
        model.showSlice(slice(generation: 1, flipped: true))
        #expect(model.renderKey == shown && model.slice?.values == before, "same generation, same slice: a host bumps it")
        model.showSlice(slice(generation: 2))
        #expect(model.renderKey != shown, "new values redraw")
        model.showSlice(nil)
        #expect(model.slice == nil && model.renderKey == key)
    }

    @Test func aSliceIsNoPartOfTheScene() async throws {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        let bounds = try #require(model.sceneBounds)
        let items = model.items.count
        let without = model.frame(at: 0)
        model.showSlice(slice())
        #expect(model.sceneBounds == bounds && model.items.count == items, "the slice neither widens nor adds to the scene")
        let with = model.frame(at: 0)
        #expect(with.slice != nil && without.slice == nil)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let picker = try ViewportPicker(renderer: try ViewportRenderer(device: device))
        var hits = 0
        for x in stride(from: 20.0, to: 380.0, by: 20.0) {
            for y in stride(from: 20.0, to: 280.0, by: 20.0) {
                let point = ScreenPoint(x, y)
                let picked = picker.pick(at: point, in: with)
                if picked != nil { hits += 1 }
                #expect(picked == picker.pick(at: point, in: without), "(\(x), \(y)): the slice is never under a pick")
            }
        }
        #expect(hits > 0, "the part itself is still picked")
        #expect(MemoryLayout<SliceUniforms>.stride == 64)
        let uniforms = SliceUniforms(slice())
        #expect(uniforms.across == SIMD4<Float>(10, 0, 0, 0) && uniforms.up == SIMD4<Float>(0, 0, 10, 0))
        #expect(uniforms.origin == SIMD4<Float>(0, 0, 15, 1) && uniforms.style.x == 0.85)
    }
}
#endif

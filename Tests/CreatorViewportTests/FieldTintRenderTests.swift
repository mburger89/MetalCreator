import CreatorGeometry
import CreatorKernel
import Metal
import Testing
@testable import CreatorViewport

/// Spec §8: "one headless render test that the tint changes pixels". `OffscreenRenderTests`' front view of a 10 × 20 × 30 box
/// (5 points per mm): its front face fills view x 75…125, y 25…175, and a vertex's x, from −5 to 5, is its field value.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct FieldTintRenderTests {
    static let bounds = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))
    static let mesh = TestMeshes.box(bounds)
    /// Red at x = −5, green at 0, blue at 5.
    static let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -5...5)

    func frame(values: [Float]? = nil, isGhost: Bool = false) -> ViewportFrame {
        var frame = TestFrames.frame(mesh: Self.mesh, pose: OffscreenRenderTests.front, size: OffscreenRenderTests.size,
                                     bounds: Self.bounds)
        frame.items[0].isGhost = isGhost
        frame.items[0].fieldValues = values
        frame.items[0].fieldRamp = values == nil ? nil : Self.ramp
        return frame
    }

    var xValues: [Float] { Self.mesh.positions.map { Float($0.x) } }

    /// The colour at view point (`x`, `y`) of the 400 × 400 target (2 pixels per point), as red, green and blue.
    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    @Test func theFrontFaceTakesTheRampLeftToRight() throws {
        let bytes = try RendererCacheTests.Rig().draw(frame(values: xValues))
        let left = color(bytes, 80, 100), middle = color(bytes, 100, 100), right = color(bytes, 120, 100)
        #expect(left[0] > left[1] + 40 && left[0] > left[2] + 60, "red towards x = −5: \(left)")
        #expect(middle[1] > middle[0] + 40 && middle[1] > middle[2] + 40, "green in the middle: \(middle)")
        #expect(right[2] > right[0] + 60 && right[2] > right[1] + 40, "blue towards x = 5: \(right)")
    }

    @Test func theTintChangesThePixelsOfThePlainSurface() throws {
        let rig = try RendererCacheTests.Rig()
        let plain = try rig.draw(frame())
        let tinted = try rig.draw(frame(values: xValues))
        let before = color(plain, 80, 100)
        #expect(abs(before[0] - before[2]) < 40, "the plain surface is a lavender grey: \(before)")
        #expect(plain != tinted)
        #expect(color(plain, 100, 190) == color(tinted, 100, 190), "off the part, the background is the same")
    }

    @Test func valuesOfTheWrongCountOrNoneDrawThePlainSurface() throws {
        let rig = try RendererCacheTests.Rig()
        let plain = try rig.draw(frame())
        #expect(try rig.draw(frame(values: [1, 2, 3])) == plain)
        #expect(try rig.draw(frame(values: [])) == plain)
    }

    @Test func aGhostIsNeverTinted() throws {
        let rig = try RendererCacheTests.Rig()
        #expect(try rig.draw(frame(values: xValues, isGhost: true)) == rig.draw(frame(isGhost: true)))
    }

    @Test func valuesThatAreNotNumbersDrawTheMiddleOfTheRamp() throws {
        let nothing = [Float](repeating: .nan, count: Self.mesh.positions.count)
        let bytes = try RendererCacheTests.Rig().draw(frame(values: nothing))
        let middle = color(bytes, 100, 100)
        #expect(middle[1] > middle[0] + 40 && middle[1] > middle[2] + 40, "green: \(middle)")
    }

    @Test func theValueBufferIsKeptUntilTheValuesChange() throws {
        let rig = try RendererCacheTests.Rig()
        _ = try rig.draw(frame(values: xValues))
        _ = try rig.draw(frame(values: xValues))
        #expect(rig.renderer.meshes[1]?.fieldUploads == 1, "the same values: one upload")
        _ = try rig.draw(frame(values: xValues.map { $0 * 0.5 }))
        #expect(rig.renderer.meshes[1]?.fieldUploads == 2)
        _ = try rig.draw(frame())
        #expect(rig.renderer.meshes[1]?.fieldUploads == 2, "a plain frame uploads nothing")
    }

    @Test func theIDPassStillSeesATintedPart() throws {
        var tinted = frame(values: xValues)
        tinted.items[0].fieldRamp = Self.ramp
        let device = try #require(MTLCreateSystemDefaultDevice())
        let picker = try ViewportPicker(renderer: try ViewportRenderer(device: device))
        #expect(picker.pick(at: ScreenPoint(100, 100), in: tinted) == .face(solid: 0, FaceID(2)), "the front face, as untinted")
    }
}

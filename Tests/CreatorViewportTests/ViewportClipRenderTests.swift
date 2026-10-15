#if canImport(Metal)
import CreatorGeometry
import CreatorKernel
import Metal
import Testing
@testable import CreatorViewport

/// The cut view in the renderer (implicit spec §5.1): the front half of a part cut away shows the inside of its far wall, darkened;
/// everything cut away draws what an empty scene does; the pick sees only what is left; a check's warning faces take the theme's
/// warning colour. The front view of `OffscreenRenderTests` (orthographic, 5 points per mm) puts a 10 × 20 × 30 box at view
/// x 75…125, y 25…175.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct ViewportClipRenderTests {
    static let bounds = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))

    func frame(clip: ViewportClip? = nil, warning: Set<FaceID> = [], empty: Bool = false) -> ViewportFrame {
        var frame = TestFrames.frame(mesh: TestMeshes.box(Self.bounds), pose: OffscreenRenderTests.front,
                                     size: OffscreenRenderTests.size, bounds: Self.bounds)
        if empty { frame.items = [] }
        frame.clip = clip
        if !frame.items.isEmpty { frame.items[0].warningFaces = warning }
        return frame
    }

    /// Cuts away everything at y below `y` (the near half of the box seen from the front for y = 0).
    func nearSide(_ y: Double) -> ViewportClip {
        ViewportClip(origin: Vector3(0, y, 0), normal: Vector3(0, -1, 0))
    }

    /// A palette colour as the bytes the target holds: red, green, blue.
    func bytes(_ colour: SIMD4<Float>) -> [Int] {
        [colour.x, colour.y, colour.z].map { Int(($0 * 255).rounded()) }
    }

    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    @Test func aPlaneBehindThePartCutsNothing() throws {
        let rig = try RendererCacheTests.Rig()
        #expect(try rig.draw(frame(clip: nearSide(-50))) == rig.draw(frame()))
    }

    @Test func cuttingTheNearHalfShowsTheInsideOfTheFarWallInTheDarkenedPartColour() throws {
        let rig = try RendererCacheTests.Rig()
        let plain = try rig.draw(frame()), cut = try rig.draw(frame(clip: nearSide(0)))
        let palette = ViewportPalette.dracula
        let expected = bytes((palette.shadeDark + palette.shadeLight) * 0.5 * 0.55)
        let inside = color(cut, 100, 100)
        #expect(inside != color(plain, 100, 100))
        for channel in 0..<3 { #expect(abs(inside[channel] - expected[channel]) <= 3, "\(inside) against \(expected)") }
        #expect(color(cut, 30, 100) == color(plain, 30, 100), "beside the part nothing changes")
    }

    @Test func cuttingEverythingDrawsWhatAnEmptySceneDraws() throws {
        let rig = try RendererCacheTests.Rig()
        #expect(try rig.draw(frame(clip: nearSide(100))) == rig.draw(frame(empty: true)), "the faces and the edges both go")
    }

    @Test func thePickSeesOnlyWhatIsLeft() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let picker = try ViewportPicker(renderer: try ViewportRenderer(device: device))
        let point = ScreenPoint(100, 100)
        #expect(picker.pick(at: point, in: frame()) == .face(solid: 0, FaceID(2)), "the front face")
        let inside = picker.pick(at: point, in: frame(clip: nearSide(0)))
        #expect(inside == .face(solid: 0, FaceID(4)), "the back face, seen from inside: \(String(describing: inside))")
        #expect(picker.pick(at: point, in: frame(clip: nearSide(100))) == nil)
    }

    @Test func aWarningFaceTakesTheThemesWarningColour() throws {
        let rig = try RendererCacheTests.Rig()
        let plain = color(try rig.draw(frame()), 100, 100)
        let flagged = color(try rig.draw(frame(warning: [FaceID(2)])), 100, 100)
        let warning = bytes(ViewportPalette.dracula.warning)
        func distance(_ c: [Int]) -> Int { (0..<3).map { abs(c[$0] - warning[$0]) }.reduce(0, +) }
        #expect(flagged != plain && distance(flagged) < distance(plain) / 2, "\(flagged) against \(plain) and \(warning)")
        let others = try rig.draw(frame(warning: [FaceID(2)]))
        #expect(color(others, 30, 100) == color(try rig.draw(frame()), 30, 100))
    }
}
#endif

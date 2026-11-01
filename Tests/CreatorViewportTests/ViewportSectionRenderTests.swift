#if canImport(Metal)
import CreatorGeometry
import CreatorKernel
import Metal
import Testing
@testable import CreatorViewport

/// The section's cap in the Metal renderer (section spec part B). The front view of `OffscreenRenderTests` (orthographic, 5 points
/// per mm) puts a 10 × 20 × 30 box at view x 75…125, y 25…175; the kept half of a cut at y = 0 shows its far wall.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct ViewportSectionRenderTests {
    static let bounds = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))

    /// The box's cross-section on the plane y = `y`, filling the whole 10 × 30 rectangle, with its outline.
    func section(y: Double) -> ViewportSection {
        let corners = [Vector3(-5, y, 0), Vector3(5, y, 0), Vector3(5, y, 30), Vector3(-5, y, 30)]
        let cap = ViewportSection.Cap(positions: corners, triangles: [0, 1, 2, 0, 2, 3], outlines: [corners + [corners[0]]],
                                      hatchAngle: ViewportSection.hatchAngle(forCap: 0))
        return ViewportSection(caps: [cap], plane: Plane(origin: Vector3(0, y, 0), normal: Vector3(0, -1, 0), xAxis: .unitX),
                               generation: 1)
    }

    func frame(section: ViewportSection? = nil, clip: ViewportClip? = nil) -> ViewportFrame {
        var frame = TestFrames.frame(mesh: TestMeshes.box(Self.bounds), pose: OffscreenRenderTests.front,
                                     size: OffscreenRenderTests.size, bounds: Self.bounds)
        frame.section = section
        frame.clip = clip
        return frame
    }

    func nearSide(_ y: Double) -> ViewportClip {
        ViewportClip(origin: Vector3(0, y, 0), normal: Vector3(0, -1, 0))
    }

    func bytes(_ colour: SIMD4<Float>) -> [Int] {
        [colour.x, colour.y, colour.z].map { Int(($0 * 255).rounded()) }
    }

    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    func matches(_ colour: [Int], _ wanted: SIMD4<Float>) -> Bool {
        zip(colour, bytes(wanted)).allSatisfy { abs($0 - $1) <= 3 }
    }

    /// Whether `colour` lies between the two colours, channel by channel (the hatch's antialiased edge is a blend).
    func between(_ colour: [Int], _ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Bool {
        let (low, high) = (bytes(a), bytes(b))
        return (0..<3).allSatisfy { colour[$0] >= min(low[$0], high[$0]) - 3 && colour[$0] <= max(low[$0], high[$0]) + 3 }
    }

    @Test func aPaletteChangeKeepsTheCapBuffers() throws {
        let rig = try RendererCacheTests.Rig()
        try rig.draw(frame(section: section(y: 1e-4), clip: nearSide(0)))
        let before = try #require(rig.renderer.sectionCache)
        var recoloured = frame(section: section(y: 1e-4), clip: nearSide(0))
        recoloured.palette.sectionEdge = SIMD4(1, 0, 0, 1)
        try rig.draw(recoloured)
        let after = try #require(rig.renderer.sectionCache)
        #expect(after.caps[0].buffer === before.caps[0].buffer, "the cap's vertices were kept")
        #expect(after.lines?.buffer !== before.lines?.buffer, "the outlines were rebuilt in the new colour")
        try rig.draw(recoloured)
        #expect(rig.renderer.sectionCache?.lines?.buffer === after.lines?.buffer, "an unchanged frame rebuilds nothing")
    }

    @Test func aCapFillsTheCutWithTheSectionColours() throws {
        let rig = try RendererCacheTests.Rig()
        let palette = ViewportPalette.dracula
        let pixels = try rig.draw(frame(section: section(y: 1e-4), clip: nearSide(0)))
        var fills = 0, hatches = 0
        // Below the view cube, which covers the top left.
        for y in 100..<140 {
            for x in 82..<122 {
                let c = color(pixels, x, y)
                if matches(c, palette.sectionFill) { fills += 1 } else if matches(c, palette.sectionHatch) { hatches += 1 } else if between(
                    c, palette.sectionFill, palette.sectionHatch) { continue } else {
                    Issue.record("pixel \(x),\(y) is \(c), neither the fill, the hatch nor a blend of them")
                    return
                }
            }
        }
        #expect(fills > 0 && hatches > 0, "\(fills) fill and \(hatches) hatch pixels")
    }

    @Test func aCapCoplanarWithAFaceShowsNotTheFace() throws {
        let rig = try RendererCacheTests.Rig()
        let palette = ViewportPalette.dracula
        let pixels = try rig.draw(frame(section: section(y: -10 + 1e-4)))
        let c = color(pixels, 100, 100)
        #expect(matches(c, palette.sectionFill) || matches(c, palette.sectionHatch), "\(c)")
    }

    @Test func aCapBehindThePartIsHidden() throws {
        let rig = try RendererCacheTests.Rig()
        let without = try rig.draw(frame())
        let with = try rig.draw(frame(section: section(y: 0)))
        #expect(color(with, 100, 100) == color(without, 100, 100))
    }

    @Test func anOldCapBeyondTheClipIsDiscarded() throws {
        let rig = try RendererCacheTests.Rig()
        #expect(try rig.draw(frame(section: section(y: -5), clip: nearSide(0))) == rig.draw(frame(clip: nearSide(0))))
    }

    @Test func outlinesDrawInTheEdgeColour() throws {
        let rig = try RendererCacheTests.Rig()
        let pixels = try rig.draw(frame(section: section(y: 1e-4), clip: nearSide(0)))
        let without = try rig.draw(frame(clip: nearSide(0)))
        // The cap's left edge runs down x = 75 from y = 25 to 175.
        #expect(matches(color(pixels, 75, 100), ViewportPalette.dracula.sectionEdge), "\(color(pixels, 75, 100))")
        #expect(color(pixels, 75, 100) != color(without, 75, 100))
    }

    @Test func aClickOnTheCapPicksNothing() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let picker = try ViewportPicker(renderer: try ViewportRenderer(device: device))
        let point = ScreenPoint(100, 100)
        let clip = nearSide(0)
        #expect(picker.pick(at: point, in: frame(clip: clip)) == .face(solid: 0, FaceID(4)), "the far wall without the cap")
        #expect(picker.pick(at: point, in: frame(section: section(y: 1e-4), clip: clip)) == nil)
    }
}
#endif

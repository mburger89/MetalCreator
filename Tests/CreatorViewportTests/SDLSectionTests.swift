#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The section's cap on SDL_GPU, as `ViewportSectionRenderTests` reads it on Metal. `RenderFixtures`' front view (orthographic, 5 points
/// per mm) puts a 10 × 20 × 30 box at view x 75…125, y 25…175; the kept half of a cut at y = 0 shows its far wall.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLSectionTests {
    typealias Rig = SDLRenderRig

    /// The box's cross-section on the plane y = `y`, filling the whole 10 × 30 rectangle, with its outline.
    func section(y: Double) -> ViewportSection {
        let corners = [Vector3(-5, y, 0), Vector3(5, y, 0), Vector3(5, y, 30), Vector3(-5, y, 30)]
        let cap = ViewportSection.Cap(positions: corners, triangles: [0, 1, 2, 0, 2, 3], outlines: [corners + [corners[0]]],
                                      hatchAngle: ViewportSection.hatchAngle(forCap: 0))
        return ViewportSection(caps: [cap], plane: Plane(origin: Vector3(0, y, 0), normal: Vector3(0, -1, 0), xAxis: .unitX),
                               generation: 1)
    }

    func frame(section: ViewportSection? = nil, clip: ViewportClip? = nil) -> ViewportFrame {
        var frame = RenderFixtures.boxFrame()
        frame.section = section
        frame.clip = clip
        return frame
    }

    func nearSide(_ y: Double) -> ViewportClip {
        ViewportClip(origin: Vector3(0, y, 0), normal: Vector3(0, -1, 0))
    }

    func matches(_ colour: [Int], _ wanted: SIMD4<Float>) -> Bool {
        zip(colour, Rig.bytes(wanted)).allSatisfy { abs($0 - $1) <= 3 }
    }

    /// Whether `colour` lies between the two colours, channel by channel (the hatch's antialiased edge is a blend).
    func between(_ colour: [Int], _ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Bool {
        let (low, high) = (Rig.bytes(a), Rig.bytes(b))
        return (0..<3).allSatisfy { colour[$0] >= min(low[$0], high[$0]) - 3 && colour[$0] <= max(low[$0], high[$0]) + 3 }
    }

    @Test func aPaletteChangeKeepsTheCapBuffers() async throws {
        let rig = try Rig()
        try await rig.draw(frame(section: section(y: 1e-4), clip: nearSide(0)))
        let before = try #require(rig.renderer.sectionBuffers)
        var recoloured = frame(section: section(y: 1e-4), clip: nearSide(0))
        recoloured.palette.sectionEdge = SIMD4(1, 0, 0, 1)
        try await rig.draw(recoloured)
        let after = try #require(rig.renderer.sectionBuffers)
        #expect(after.caps[0].buffer === before.caps[0].buffer, "the cap's vertices were kept")
        #expect(after.lines?.buffer !== before.lines?.buffer, "the outlines were rebuilt in the new colour")
    }

    @Test func aCapFillsTheCutWithTheSectionColours() async throws {
        let pixels = try await Rig().draw(frame(section: section(y: 1e-4), clip: nearSide(0)))
        let palette = ViewportPalette.dracula
        var fills = 0, hatches = 0
        // Below the view cube, which covers the top left.
        for y in 100..<140 {
            for x in 82..<122 {
                let c = Rig.color(pixels, x, y)
                if matches(c, palette.sectionFill) { fills += 1 } else if matches(c, palette.sectionHatch) { hatches += 1 } else if between(
                    c, palette.sectionFill, palette.sectionHatch) { continue } else {
                    Issue.record("pixel \(x),\(y) is \(c), neither the fill, the hatch nor a blend of them")
                    return
                }
            }
        }
        #expect(fills > 0 && hatches > 0, "\(fills) fill and \(hatches) hatch pixels")
    }

    @Test func aCapCoplanarWithAFaceShowsNotTheFace() async throws {
        let pixels = try await Rig().draw(frame(section: section(y: -10 + 1e-4)))
        let c = Rig.color(pixels, 100, 100)
        #expect(matches(c, ViewportPalette.dracula.sectionFill) || matches(c, ViewportPalette.dracula.sectionHatch), "\(c)")
    }

    @Test func aCapBehindThePartIsHidden() async throws {
        let rig = try Rig()
        let without = try await rig.draw(frame())
        let with = try await rig.draw(frame(section: section(y: 0)))
        #expect(Rig.color(with, 100, 100) == Rig.color(without, 100, 100))
    }

    @Test func anOldCapBeyondTheClipIsDiscarded() async throws {
        let rig = try Rig()
        let with = try await rig.draw(frame(section: section(y: -5), clip: nearSide(0)))
        let without = try await rig.draw(frame(clip: nearSide(0)))
        #expect(with == without)
    }

    @Test func outlinesDrawInTheEdgeColour() async throws {
        let rig = try Rig()
        let with = try await rig.draw(frame(section: section(y: 1e-4), clip: nearSide(0)))
        let without = try await rig.draw(frame(clip: nearSide(0)))
        // The cap's left edge runs down x = 75 from y = 25 to 175.
        let c = Rig.color(with, 75, 100)
        #expect(matches(c, ViewportPalette.dracula.sectionEdge), "\(c)")
        #expect(c != Rig.color(without, 75, 100))
    }

    @Test func aClickOnTheCapPicksNothing() async throws {
        let rig = try Rig()
        let point = ScreenPoint(100, 100)
        let clip = nearSide(0)
        #expect(try await rig.pick(at: point, in: frame(clip: clip)) == .face(solid: 0, FaceID(4)), "the far wall without the cap")
        #expect(try await rig.pick(at: point, in: frame(section: section(y: 1e-4), clip: clip)) == nil)
    }
}
#endif

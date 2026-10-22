#if canImport(MetalUISDLGPU)
import CreatorGeometry
import MetalUISDLGPU
import Testing
@testable import CreatorViewport

/// The view cube and the triad on SDL_GPU, each drawn into a square of the target with a camera of its own (`SDLGPURenderPass.setViewport`).
/// With `RenderFixtures`' 200 × 200 point view at 2 pixels per point, the cube is 96 points at (16, 16) and the triad 64 points at
/// (16, 120). The faces' names are a texture painted on the cube (`CubeLabelAtlas`).
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLWidgetTests {
    typealias Rig = SDLRenderRig

    /// The red channel of every pixel of a draw of `frame` in the front view, row by row.
    func redChannel(_ rig: Rig, _ frame: ViewportFrame) async throws -> [UInt8] {
        let bytes = try await rig.draw(frame)
        return stride(from: 2, to: bytes.count, by: 4).map { bytes[$0] }   // bgra: red is byte 2
    }

    /// The one test that reads colours back from the cube: its FRONT label is painted on the FRONT face. Looking from the front, the
    /// face is the cyan active region, and the #f8f8f2 ink (red ≈ 248, against cyan's 139) shows across the middle of the face and
    /// nowhere near its rim. Seen from behind, FRONT is culled.
    @Test func theFrontLabelIsPaintedOnTheFrontFace() async throws {
        let rig = try Rig()
        // The cube is 96 points at (16, 16), 2 pixels per point: centred on pixel (128, 128), with a face spanning ±96 / 1.8 ≈ ±53
        // pixels. The text box is ±0.8 of the face across and ±0.3 of it up and down.
        func inked(_ red: [UInt8], xs: ClosedRange<Int>, ys: ClosedRange<Int>) -> Int {
            ys.reduce(0) { count, y in count + xs.count { red[y * 400 + $0] > 195 } }
        }
        let fromFront = try await redChannel(rig, RenderFixtures.emptyFrame())
        let text = inked(fromFront, xs: 88...168, ys: 116...140)
        #expect(text > 150, "label ink across the middle of FRONT (\(text) pixels)")
        #expect(inked(fromFront, xs: 80...176, ys: 154...172) == 0, "no ink between the text and the face's rim")
        var behind = RenderFixtures.emptyFrame()
        behind.pose.yaw = .pi
        let fromBehind = try await redChannel(rig, behind)
        #expect(inked(fromBehind, xs: 88...168, ys: 116...140) > 150, "BACK's own label shows from behind")
        #expect(fromBehind != fromFront, "and FRONT's doesn't show through it")
    }

    /// A machine with no installed font (a minimal container, Windows Server Core) has no face names to paint; the cube still draws.
    @Test func aBlankAtlasLeavesTheCubeDrawnButUnlabelled() async throws {
        let blank = try Rig(labelAtlas: .blank)
        let red = try await redChannel(blank, RenderFixtures.emptyFrame())
        let inked = (116...140).reduce(0) { count, y in count + (88...168).count { red[y * 400 + $0] > 195 } }
        #expect(inked == 0, "no label ink (\(inked) pixels)")
        var hidden = RenderFixtures.emptyFrame()
        hidden.showsViewCube = false
        let withCube = try await blank.draw(RenderFixtures.emptyFrame())
        #expect(Rig.color(withCube, 64, 64) != Rig.color(try await blank.draw(hidden), 64, 64), "the cube's tiles are there")
        #expect(try await Rig().draw(RenderFixtures.emptyFrame()) != withCube, "and the labelled cube differs")
    }

    @Test func theCubeStaysInsideItsSquareAndIsHiddenWhenAskedTo() async throws {
        let rig = try Rig()
        let shown = try await rig.draw(RenderFixtures.emptyFrame())
        var hidden = RenderFixtures.emptyFrame()
        hidden.showsViewCube = false
        let without = try await rig.draw(hidden)
        #expect(Rig.color(shown, 64, 64) != Rig.color(without, 64, 64), "the cube covers the middle of its square")
        #expect(Rig.color(shown, 130, 64) == Rig.color(without, 130, 64), "and not the view beside it")
        #expect(Rig.color(shown, 100, 190) == Rig.color(without, 100, 190), "nor the bottom of the view")
    }

    @Test func aHoveredRegionChangesThePixelsOfTheCubeAndNoOthers() async throws {
        let rig = try Rig()
        var hovered = RenderFixtures.emptyFrame()
        hovered.pose = CameraPose(target: Vector3(0, 0, 15), distance: RenderFixtures.front.distance, yaw: 0.6, pitch: 0.4,
                                  projection: .orthographic)
        let plain = try await rig.draw(hovered)
        hovered.hoveredCubeRegion = .top
        let tinted = try await rig.draw(hovered)
        #expect(plain != tinted)
        #expect(Rig.color(plain, 100, 190) == Rig.color(tinted, 100, 190), "off the cube nothing changes")
    }

    @Test func theTriadDrawsItsThreeAxesInTheirColoursInItsOwnSquare() async throws {
        let rig = try Rig()
        var turned = RenderFixtures.emptyFrame()
        turned.pose = CameraPose(target: Vector3(0, 0, 15), distance: RenderFixtures.front.distance, yaw: 0.6, pitch: 0.4,
                                 projection: .orthographic)
        let bytes = try await rig.draw(turned)
        let palette = ViewportPalette.dracula
        // The triad's square: x 16…80, y 120…184 points (the view is 200 points tall; the bottom margin is 16).
        func near(_ colour: SIMD4<Float>) -> Int {
            let want = Rig.bytes(colour)
            var count = 0
            for y in 120..<184 {
                for x in 16..<80 {
                    let pixel = Rig.color(bytes, x, y)
                    if zip(pixel, want).allSatisfy({ abs($0 - $1) <= 24 }) { count += 1 }
                }
            }
            return count
        }
        #expect(near(palette.axisX) > 8, "red axis")
        #expect(near(palette.axisY) > 8, "green axis")
        #expect(near(palette.axisZ) > 8, "blue axis")
        #expect(Rig.color(bytes, 150, 150) == Rig.color(try await rig.draw(turned), 150, 150))
    }

    @Test func theTriadAndCubeBuffersSurviveAnOrbitAndFollowThePalette() async throws {
        let rig = try Rig()
        try await rig.draw(RenderFixtures.emptyFrame())
        let first = try #require(rig.renderer.triadBuffer)
        var orbited = RenderFixtures.emptyFrame()
        orbited.pose.yaw += 0.3
        try await rig.draw(orbited)
        #expect(try #require(rig.renderer.triadBuffer).buffer === first.buffer, "an orbit turns the widget's camera, not its instances")
        var other = RenderFixtures.emptyFrame()
        other.palette = ViewportPalette(.alucard)
        try await rig.draw(other)
        #expect(try #require(rig.renderer.triadBuffer).buffer !== first.buffer)
    }

    @Test func aWidgetThatDoesNotFitTheTargetIsLeftOut() async throws {
        let rig = try Rig()
        var cramped = RenderFixtures.emptyFrame()
        cramped.cube = ViewCubeLayout(origin: ScreenPoint(150, 16), side: 96)   // runs past the view's right edge
        cramped.triad = TriadLayout(side: 64, leading: 150, bottom: 16)
        let drawn = try await rig.draw(cramped)
        var hidden = cramped
        hidden.showsViewCube = false
        #expect(drawn[0..<64] == (try await rig.draw(hidden))[0..<64])
        #expect(rig.renderer.encodedPasses == 2, "the pass itself still runs")
    }
}
#endif

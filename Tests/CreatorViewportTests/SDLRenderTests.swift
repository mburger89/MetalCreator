#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import Foundation
import MetalUISDLGPU
import Testing
@testable import CreatorViewport

/// The main pass on SDL_GPU, as the Metal one in `OffscreenRenderTests`: pixels read back from a 400 × 400 target at 2 pixels per
/// point. `RenderFixtures`' front view (orthographic, 5 points per mm) puts a 10 × 20 × 30 box at view x 75…125, y 25…175. The
/// colours are far apart (a lavender-grey surface, the white edges, the dark background), so the tests compare regions and
/// palette colours with a margin, never exact pixels.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLRenderTests {
    typealias Rig = SDLRenderRig
    let palette = ViewportPalette.dracula

    /// How many pixels of view row `row` (x 5…194) are not `colour`.
    static func pixelsDiffering(from colour: [Int], inRow row: Int, of bytes: [UInt8]) -> Int {
        (5..<195).count { Rig.color(bytes, $0, row) != colour }
    }

    @Test func theBackgroundIsAGradientFromTheTopColourToTheBottomOne() async throws {
        let rig = try Rig()
        let bytes = try await rig.draw(RenderFixtures.emptyFrame())
        let top = Rig.color(bytes, 100, 1), bottom = Rig.color(bytes, 100, 198)
        let expectedTop = Rig.bytes(palette.backgroundTop), expectedBottom = Rig.bytes(palette.backgroundBottom)
        for channel in 0..<3 {
            #expect(abs(top[channel] - expectedTop[channel]) <= 4, "top \(top) against \(expectedTop)")
            #expect(abs(bottom[channel] - expectedBottom[channel]) <= 4, "bottom \(bottom) against \(expectedBottom)")
        }
    }

    @Test func aSolidIsDrawnWhereItStandsAndTheBackgroundIsLeftAroundIt() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(RenderFixtures.emptyFrame())
        let boxed = try await rig.draw(RenderFixtures.boxFrame())
        #expect(Rig.color(boxed, 100, 100) != Rig.color(plain, 100, 100), "the front face covers the middle")
        let face = Rig.color(boxed, 85, 100)
        #expect(abs(face[0] - face[2]) < 60 && face[0] > 60, "a lavender grey, lit: \(face)")
        #expect(Rig.color(boxed, 30, 100) == Rig.color(plain, 30, 100), "left of the part nothing changes")
        #expect(Rig.color(boxed, 170, 100) == Rig.color(plain, 170, 100), "right of the part nothing changes")
        #expect(Rig.color(boxed, 100, 190) == Rig.color(plain, 100, 190), "below the part nothing changes")
    }

    @Test func theBoxSitsWhereTheCameraPutsItTopEdgeUp() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(RenderFixtures.emptyFrame())
        let boxed = try await rig.draw(RenderFixtures.boxFrame())
        #expect(Rig.color(boxed, 100, 30) != Rig.color(plain, 100, 30), "just inside the top edge (view y 25)")
        #expect(Rig.color(boxed, 100, 20) == Rig.color(plain, 100, 20), "just above it")
        #expect(Rig.color(boxed, 100, 170) != Rig.color(plain, 100, 170), "just inside the bottom edge (view y 175)")
        #expect(Rig.color(boxed, 100, 180) == Rig.color(plain, 100, 180), "just below it")
    }

    @Test func edgesDrawOverTheSolidInTheEdgeColourAndShadedModeKeepsOnlyTheSelectedOnes() async throws {
        let rig = try Rig()
        var frame = RenderFixtures.boxFrame()
        let edge = try await rig.draw(frame)
        #expect(Rig.color(edge, 100, 25)[1] > 230, "the top front edge is white: \(Rig.color(edge, 100, 25))")
        frame.shading = .shaded
        let shaded = try await rig.draw(frame)
        #expect(Rig.color(shaded, 100, 25)[1] < 200, "Shaded draws no edges: \(Rig.color(shaded, 100, 25))")
        frame.items[0].selectedEdges = [EdgeID(1)]
        let selected = try await rig.draw(frame)
        let pink = Rig.color(selected, 100, 25)
        #expect(pink[0] > 200 && pink[2] > 150 && pink[1] < 170, "a rule's edge still shows, in the selection pink: \(pink)")
    }

    @Test func hoverSelectionAndWarningTintTheFaceTheyNameAndNoOther() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(RenderFixtures.boxFrame())
        var hovered = RenderFixtures.boxFrame()
        hovered.items[0].hoveredFace = FaceID(2)
        var selected = RenderFixtures.boxFrame()
        selected.items[0].selectedFaces = [FaceID(2)]
        var warned = RenderFixtures.boxFrame()
        warned.items[0].warningFaces = [FaceID(2)]
        let before = Rig.color(plain, 100, 100)
        let hover = Rig.color(try await rig.draw(hovered), 100, 100)
        let pick = Rig.color(try await rig.draw(selected), 100, 100)
        let warn = Rig.color(try await rig.draw(warned), 100, 100)
        #expect(hover != before && hover[1] >= before[1] && hover[2] >= before[2], "cyan creeps in: \(hover) from \(before)")
        #expect(pick[0] > before[0] + 30 && pick[1] < hover[1] + 40, "pink: \(pick) from \(before)")
        let warning = Rig.bytes(palette.warning)
        func distance(_ c: [Int]) -> Int { (0..<3).map { abs(c[$0] - warning[$0]) }.reduce(0, +) }
        #expect(distance(warn) < distance(before) / 2, "the warning colour: \(warn) against \(warning) and \(before)")
        let other = try await rig.draw(selected)
        #expect(Rig.color(other, 30, 100) == Rig.color(plain, 30, 100), "off the part nothing changes")
    }

    @Test func aGhostIsDimmedAndBlendedOverWhatIsBehindIt() async throws {
        let rig = try Rig()
        var ghost = RenderFixtures.boxFrame()
        ghost.items[0].isGhost = true
        let solid = Rig.color(try await rig.draw(RenderFixtures.boxFrame()), 85, 100)
        let ghostly = Rig.color(try await rig.draw(ghost), 85, 100)
        let background = Rig.color(try await rig.draw(RenderFixtures.emptyFrame()), 85, 100)
        #expect(ghostly != solid && ghostly != background)
        for channel in 0..<3 {
            let low = min(solid[channel], background[channel]) - 30, high = max(solid[channel], background[channel]) + 30
            #expect((low...high).contains(ghostly[channel]), "the 40% ghost lies between the part and the background: \(ghostly)")
        }
    }

    // MARK: Meshes at the extremes

    /// A Mesh node can come out empty (a scatter of nothing, a failed mesh) or bare of edges; neither may trap, and what is there draws.
    @Test func aMeshWithNoTrianglesOrNoEdgesDrawsWhatItHasAndDoesNotTrap() async throws {
        let rig = try Rig()
        let background = try await rig.draw(RenderFixtures.emptyFrame())
        var nothing = RenderFixtures.boxFrame()
        nothing.items[0].mesh = DisplayMesh(positions: [], normals: [], indices: [], triangleFaces: [], edgePolylines: [:])
        #expect(try await rig.draw(nothing) == background, "a mesh with no triangles draws nothing")
        let box = TestMeshes.box(RenderFixtures.bounds)
        var bare = RenderFixtures.boxFrame()
        bare.items[0].mesh = DisplayMesh(positions: box.positions, normals: box.normals, indices: box.indices,
                                         triangleFaces: box.triangleFaces, edgePolylines: [:])
        bare.items[0].meshSerial = 3
        let drawn = try await rig.draw(bare)
        #expect(Rig.color(drawn, 100, 100) != Rig.color(background, 100, 100), "the faces draw")
        #expect(Rig.color(drawn, 100, 25)[1] < 200, "and there is no white edge on the top: \(Rig.color(drawn, 100, 25))")
    }

    /// 7c's previews run to millions of triangles; a hundred thousand is a quick test of the same path (3 × 100,352 corners at 48 bytes).
    @Test func aLargeMeshDrawsAndKeepsAllItsCorners() async throws {
        let rig = try Rig()
        var frame = RenderFixtures.boxFrame()
        frame.items[0].mesh = TestMeshes.sheet(RenderFixtures.bounds, columns: 224, rows: 224)
        frame.items[0].meshSerial = 4
        let drawn = try await rig.draw(frame)
        #expect(rig.renderer.meshes[4]?.vertexCount == 3 * 2 * 224 * 224)
        let background = try await rig.draw(RenderFixtures.emptyFrame())
        #expect(Rig.color(drawn, 100, 100) != Rig.color(background, 100, 100), "the sheet covers the middle")
        #expect(Rig.color(drawn, 30, 100) == Rig.color(background, 30, 100), "and only that")
    }

    /// Edge and overlay buffers bake the theme's colours in; a theme change must rebuild them, not draw the old colours.
    @Test func aNewPaletteRebuildsTheCachedEdgesInItsColours() async throws {
        let rig = try Rig()
        let before = Rig.color(try await rig.draw(RenderFixtures.boxFrame()), 100, 25)
        var light = RenderFixtures.boxFrame()
        light.palette = ViewportPalette(.alucard)
        let after = Rig.color(try await rig.draw(light), 100, 25)
        let alucardEdge = Rig.bytes(ViewportPalette(.alucard).edge)
        func distance(_ colour: [Int]) -> Int { (0..<3).map { abs(colour[$0] - alucardEdge[$0]) }.reduce(0, +) }
        #expect(after != before)
        #expect(distance(after) < distance(before), "nearer the light theme's edge colour \(alucardEdge): \(after) from \(before)")
    }

    @Test func aTargetOfTheWrongFormatOrAnEmptyViewIsLeftAlone() async throws {
        let rig = try Rig()
        let rgba = try #require(rig.device.makeTexture(SDLGPUTextureDescription(
            width: 8, height: 8, format: .r8g8b8a8Unorm, usage: [.colorTarget])))
        let boxed = Handoff(value: RenderFixtures.boxFrame())
        let renderer = rig.renderer
        var fence = try await rig.device.submitBatch { commandBuffer in
            renderer.encode(boxed.value, into: rgba, scale: 1, commandBuffer: commandBuffer)
        }
        await fence.wait()
        #expect(renderer.encodedPasses == 0, "a target in another format")
        var empty = RenderFixtures.boxFrame()
        empty.size = ViewportSize(width: 0, height: 0)
        let emptyBoxed = Handoff(value: empty)
        let target = rig.target
        fence = try await rig.device.submitBatch { commandBuffer in
            renderer.encode(emptyBoxed.value, into: target, scale: 1, commandBuffer: commandBuffer)
        }
        await fence.wait()
        #expect(renderer.encodedPasses == 0, "a view with no size")
        _ = try await rig.draw(RenderFixtures.boxFrame())
        #expect(renderer.encodedPasses == 1)
    }

    @Test func theGroundGridDrawsLinesOnTheGroundAndNotWhenTheOverlayHasAGridOfItsOwn() async throws {
        let rig = try Rig()
        var looking = RenderFixtures.emptyFrame()
        looking.pose = CameraPose(target: .zero, distance: 40 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: -.pi / 2,
                                  projection: .orthographic)
        let withGrid = try await rig.draw(looking)
        let differing = Self.pixelsDiffering(from: Rig.color(withGrid, 12, 112), inRow: 112, of: withGrid)
        #expect(differing >= 3, "grid lines cross a row of a view straight down: \(differing) pixels differ from the gap between them")
        looking.overlay = ViewportOverlay(gridPlane: .xy)
        let overlayGrid = try await rig.draw(looking)
        #expect(overlayGrid != withGrid, "a plane grid in the overlay replaces the ground grid")
    }

    @Test func aFilledOverlayTrianglesTintsThePixelsItCoversAndNoOthers() async throws {
        let rig = try Rig()
        let fill = OverlayFill(vertices: [Vector3(-6, 0, 9), Vector3(6, 0, 9), Vector3(0, 0, 21)])
        let plain = try await rig.draw(RenderFixtures.emptyFrame())
        let filled = try await rig.draw(RenderFixtures.emptyFrame(overlay: ViewportOverlay(fills: [fill])))
        let inside = zip(Rig.color(plain, 100, 100), Rig.color(filled, 100, 100)).map { abs($0 - $1) }
        #expect(inside.contains { $0 >= 3 }, "the view's centre is inside the triangle: \(inside)")
        #expect(Rig.color(plain, 20, 190) == Rig.color(filled, 20, 190), "a corner far from it is untouched")
    }

    @Test func anOverlayLineAndAHandleDrawOverTheScene() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(RenderFixtures.emptyFrame())
        let line = OverlayLine(Vector3(-10, 0, 15), Vector3(10, 0, 15), tint: .construction, isDashed: false)
        let overlay = try await rig.draw(RenderFixtures.emptyFrame(overlay: ViewportOverlay(lines: [line])))
        #expect(Rig.color(overlay, 100, 100) != Rig.color(plain, 100, 100), "the line runs through the middle")
        #expect(Rig.color(overlay, 100, 160) == Rig.color(plain, 100, 160), "and not below it")
        var handled = RenderFixtures.emptyFrame()
        handled.handles = [ViewportHandle(id: "h", anchor: Vector3(0, 0, 0), direction: .unitZ, value: 20, range: 0...50,
                                          style: .linear, tint: .solid),
        ]
        let handle = try await rig.draw(handled)
        #expect(Rig.color(handle, 100, 100) != Rig.color(plain, 100, 100), "the shaft crosses the middle")
        #expect(Rig.color(handle, 100, 75) != Rig.color(plain, 100, 75), "and the knob sits 20 mm up (view y 75)")
        #expect(Rig.color(handle, 100, 40) == Rig.color(plain, 100, 40), "with nothing above it")
    }

    @Test func aLightPaletteChangesWhatIsDrawn() async throws {
        let rig = try Rig()
        var light = RenderFixtures.boxFrame()
        light.palette = ViewportPalette(.alucard)
        let dark = Rig.color(try await rig.draw(RenderFixtures.boxFrame()), 85, 100)
        #expect(Rig.color(try await rig.draw(light), 85, 100) != dark)
    }

    // MARK: Buffers are kept between frames

    @Test func theOverlayHandleAndFillBuffersSurviveAnOrbitAndAreReleasedWhenTheirContentGoes() async throws {
        let rig = try Rig()
        let fill = OverlayFill(vertices: [Vector3(-6, 0, 9), Vector3(6, 0, 9), Vector3(0, 0, 21)])
        let line = OverlayLine(.zero, Vector3(10, 0, 10), tint: .construction, isDashed: true)
        var frame = RenderFixtures.emptyFrame(overlay: ViewportOverlay(lines: [line], fills: [fill], gridPlane: .xz))
        frame.handles = [ViewportHandle(id: "h", anchor: .zero, direction: .unitZ, value: 20, range: 0...50, style: .linear, tint: .solid)]
        try await rig.draw(frame)
        let overlay = try #require(rig.renderer.overlayBuffer), fills = try #require(rig.renderer.fillBuffer)
        let handles = try #require(rig.renderer.handleBuffer)
        frame.pose.yaw += 0.2
        try await rig.draw(frame)
        #expect(try #require(rig.renderer.overlayBuffer).buffer === overlay.buffer, "an orbit rebuilds nothing the zoom did not change")
        #expect(try #require(rig.renderer.fillBuffer).buffer === fills.buffer)
        #expect(try #require(rig.renderer.handleBuffer).buffer === handles.buffer)
        frame.pose.distance *= 2
        try await rig.draw(frame)
        #expect(try #require(rig.renderer.overlayBuffer).buffer !== overlay.buffer, "dashes and reach follow the zoom")
        try await rig.draw(RenderFixtures.emptyFrame())
        #expect(rig.renderer.fillBuffer == nil, "leaving sketch mode frees the fills")
    }

    @Test func aReusedRendererDrawsThePixelsAFreshOneDoes() async throws {
        let reused = try Rig()
        let fill = OverlayFill(vertices: [Vector3(-6, 0, 9), Vector3(6, 0, 9), Vector3(0, 0, 21)])
        var frame = RenderFixtures.boxFrame()
        frame.overlay = ViewportOverlay(fills: [fill])
        try await reused.draw(frame)
        frame.pose.yaw += 0.2
        let fromReused = try await reused.draw(frame)
        let fromFresh = try await Rig().draw(frame)
        #expect(fromReused == fromFresh)
    }
}
#endif

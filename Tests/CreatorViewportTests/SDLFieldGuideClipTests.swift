#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The field tint, the guides and the cut view on SDL_GPU (fields spec §6, spec §6.3 Errata (M6), implicit spec §5.1), as the Metal
/// `FieldTintRenderTests`, `GuideRenderTests` and `ViewportClipRenderTests` read them.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLFieldGuideClipTests {
    typealias Rig = SDLRenderRig
    static let mesh = TestMeshes.box(RenderFixtures.bounds)
    /// Red at x = −5, green at 0, blue at 5.
    static let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -5...5)
    var xValues: [Float] { Self.mesh.positions.map { Float($0.x) } }

    func tinted(values: [Float]? = nil, isGhost: Bool = false) -> ViewportFrame {
        var frame = RenderFixtures.boxFrame()
        frame.items[0].isGhost = isGhost
        frame.items[0].fieldValues = values
        frame.items[0].fieldRamp = values == nil ? nil : Self.ramp
        return frame
    }

    // MARK: Field tint

    @Test func theFrontFaceTakesTheRampLeftToRight() async throws {
        let bytes = try await Rig().draw(tinted(values: xValues))
        let left = Rig.color(bytes, 80, 100), middle = Rig.color(bytes, 100, 100), right = Rig.color(bytes, 120, 100)
        #expect(left[0] > left[1] + 40 && left[0] > left[2] + 60, "red towards x = −5: \(left)")
        #expect(middle[1] > middle[0] + 40 && middle[1] > middle[2] + 40, "green in the middle: \(middle)")
        #expect(right[2] > right[0] + 60 && right[2] > right[1] + 40, "blue towards x = 5: \(right)")
    }

    @Test func valuesOfTheWrongCountOrNoneDrawThePlainSurfaceAndAGhostIsNeverTinted() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(tinted())
        #expect(plain != (try await rig.draw(tinted(values: xValues))), "the tint changes the pixels")
        #expect(try await rig.draw(tinted(values: [1, 2, 3])) == plain)
        #expect(try await rig.draw(tinted(values: [])) == plain)
        #expect(try await rig.draw(tinted(values: xValues, isGhost: true)) == (try await rig.draw(tinted(isGhost: true))))
    }

    @Test func valuesThatAreNotNumbersDrawTheMiddleOfTheRamp() async throws {
        let nothing = [Float](repeating: .nan, count: Self.mesh.positions.count)
        let middle = Rig.color(try await Rig().draw(tinted(values: nothing)), 100, 100)
        #expect(middle[1] > middle[0] + 40 && middle[1] > middle[2] + 40, "green: \(middle)")
    }

    @Test func theValueBufferIsKeptUntilTheValuesChange() async throws {
        let rig = try Rig()
        try await rig.draw(tinted(values: xValues))
        try await rig.draw(tinted(values: xValues))
        #expect(rig.renderer.meshes[1]?.fieldUploads == 1, "the same values: one upload")
        try await rig.draw(tinted(values: xValues.map { $0 * 0.5 }))
        #expect(rig.renderer.meshes[1]?.fieldUploads == 2)
        try await rig.draw(tinted())
        #expect(rig.renderer.meshes[1]?.fieldUploads == 2, "a plain frame uploads nothing")
    }

    // MARK: Guides

    func guideFrame(withGuide guide: DisplayMesh?) -> ViewportFrame {
        var frame = RenderFixtures.boxFrame()
        if let guide {
            frame.items.append(FrameItem(meshSerial: 2, mesh: guide, solidIndex: 1, isGhost: false, hoveredFace: nil,
                                         selectedFaces: [], selectedEdges: Set(guide.edgePolylines.keys), isGuide: true))
        }
        return frame
    }

    @Test func aGuidesEdgesDrawInTheSelectionColourOverEmptySpaceAndItsSurfacesDoNot() async throws {
        let rig = try Rig()
        let wide = TestMeshes.box(BoundingBox(min: Vector3(-15, -10, 0), max: Vector3(15, 10, 30)))
        let with = try await rig.draw(guideFrame(withGuide: wide))
        let without = try await rig.draw(guideFrame(withGuide: nil))
        // The guide spans x −15…15 mm: its left edges are at view x = 25, clear of the part (x 75…125).
        let edge = Rig.color(with, 25, 100)
        #expect(edge[0] > 200 && edge[2] > 150 && edge[1] < 170, "pink: \(edge)")
        #expect(Rig.color(without, 25, 100)[0] < 100, "the dark background")
        #expect(Rig.color(with, 40, 100) == Rig.color(without, 40, 100), "inside the guide, off its edges: no surface is drawn")
        // The guide's top front edge runs along the part's, at view y = 25, between x = 75 and 125.
        #expect(Rig.color(without, 100, 25)[1] > 230, "the part's own edge is white")
        let covered = Rig.color(with, 100, 25)
        #expect(covered[0] > 200 && covered[1] < 170, "and the guide's edge glows over it: \(covered)")
    }

    @Test func anEdgeBehindThePartShowsFaintlyThroughIt() async throws {
        let rig = try Rig()
        let inside = TestMeshes.box(BoundingBox(min: Vector3(-2, -2, 0), max: Vector3(2, 2, 10)))
        let with = try await rig.draw(guideFrame(withGuide: inside))
        let without = try await rig.draw(guideFrame(withGuide: nil))
        // The guide's left edges are at view x = 90, 8 mm behind the part's front face.
        let seen = Rig.color(with, 90, 150), plain = Rig.color(without, 90, 150)
        #expect(seen[1] < plain[1] - 10, "pinker than the part's face: \(seen) against \(plain)")
        #expect(seen[1] > 121, "but fainter than the selection pink (green 121): \(seen)")
        #expect(Rig.color(with, 100, 100) == Rig.color(without, 100, 100), "the part's face between the edges is as before")
    }

    // MARK: Cut view

    func clipFrame(clip: ViewportClip? = nil, warning: Set<FaceID> = [], empty: Bool = false) -> ViewportFrame {
        var frame = RenderFixtures.boxFrame()
        if empty { frame.items = [] }
        frame.clip = clip
        if !frame.items.isEmpty { frame.items[0].warningFaces = warning }
        return frame
    }

    /// Cuts away everything at y below `y` (the near half of the box seen from the front for y = 0).
    func nearSide(_ y: Double) -> ViewportClip { ViewportClip(origin: Vector3(0, y, 0), normal: Vector3(0, -1, 0)) }

    @Test func aPlaneBehindThePartCutsNothingAndCuttingTheNearHalfShowsTheInsideOfTheFarWallDarkened() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(clipFrame())
        #expect(try await rig.draw(clipFrame(clip: nearSide(-50))) == plain)
        let cut = try await rig.draw(clipFrame(clip: nearSide(0)))
        let palette = ViewportPalette.dracula
        let expected = Rig.bytes((palette.shadeDark + palette.shadeLight) * 0.5 * 0.55)
        let inside = Rig.color(cut, 100, 100)
        #expect(inside != Rig.color(plain, 100, 100))
        for channel in 0..<3 { #expect(abs(inside[channel] - expected[channel]) <= 3, "\(inside) against \(expected)") }
        #expect(Rig.color(cut, 30, 100) == Rig.color(plain, 30, 100), "beside the part nothing changes")
    }

    @Test func cuttingEverythingDrawsWhatAnEmptySceneDraws() async throws {
        let rig = try Rig()
        #expect(try await rig.draw(clipFrame(clip: nearSide(100))) == (try await rig.draw(clipFrame(empty: true))),
                "the faces and the edges both go")
    }
}
#endif

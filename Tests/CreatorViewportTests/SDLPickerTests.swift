#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The ID pass and its read-back on SDL_GPU (spec §8's offscreen test, as `OffscreenRenderTests` runs it on Metal): the face and edge
/// IDs under chosen pixels of a known solid, from the `r32Uint` words `SDLGPUDevice.download` returns. Pixel colours are never compared.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLPickerTests {
    typealias Rig = SDLRenderRig

    @Test func theIDPassReportsTheFaceAndEdgeUnderChosenPixels() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        // TestMeshes.box: face 2 is the front (−Y), and edge 1 its top (side 0, top).
        #expect(try await rig.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)))
        #expect(rig.picker.pick(at: ScreenPoint(80, 160), in: frame) == .face(solid: 0, FaceID(2)))
        #expect(rig.picker.pick(at: ScreenPoint(100, 26), in: frame) == .edge(solid: 0, EdgeID(1)),
                "1.5 points below the top edge is inside its 6-point pick width")
        #expect(rig.picker.pick(at: ScreenPoint(100, 174), in: frame) == .edge(solid: 0, EdgeID(0)), "and the bottom edge")
        #expect(rig.picker.pick(at: ScreenPoint(100, 10), in: frame) == nil)
        #expect(rig.picker.pick(at: ScreenPoint(160, 100), in: frame) == nil)
    }

    @Test func picksOutsideTheViewOrBeforeItHasASizeAreNil() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        try await rig.prepare(frame)
        await rig.picker.refresh(frame)
        for point in [ScreenPoint(-1, 100), ScreenPoint(100, -0.5), ScreenPoint(200, 100), ScreenPoint(100, 200),
                      ScreenPoint(.nan, 3), ScreenPoint(.infinity, 3),
        ] {
            #expect(rig.picker.pick(at: point, in: frame) == nil, "\(point)")
        }
        var empty = frame
        empty.size = ViewportSize(width: 0, height: 0)
        #expect(rig.picker.pick(at: ScreenPoint(0, 0), in: empty) == nil)
        #expect(!rig.picker.isPending(for: empty), "a view with no size has nothing to wait for")
    }

    @Test func theIDBufferIsReusedUntilTheCameraMoves() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        _ = try await rig.pick(at: ScreenPoint(100, 100), in: frame)
        await rig.picker.refresh(frame)
        _ = rig.picker.pick(at: ScreenPoint(90, 120), in: frame)
        #expect(rig.picker.renderCount == 1)
        var turned = frame
        turned.pose.yaw += 0.1
        _ = try await rig.pick(at: ScreenPoint(100, 100), in: turned)
        #expect(rig.picker.renderCount == 2)
    }

    @Test func aBufferThatHasNotLandedIsPendingAndAnswersNilUntilItDoes() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        try await rig.prepare(frame)
        #expect(rig.picker.isPending(for: frame))
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == nil)
        var landed = 0
        rig.picker.onReady = { landed += 1 }
        let target = await rig.picker.pickWhenReady(at: ScreenPoint(100, 100), in: frame)
        #expect(target == .face(solid: 0, FaceID(2)))
        #expect(!rig.picker.isPending(for: frame))
        #expect(landed >= 1, "the model is told so it can look under the pointer again")
        var turned = frame
        turned.pose.yaw += 0.1
        #expect(rig.picker.isPending(for: turned), "a new camera has no buffer yet")
    }

    @Test func aFrameWhoseMeshesWereNeverUploadedLandsEmptyAndIsTriedAgainOnTheNextSchedule() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        await rig.picker.refresh(frame)
        #expect(!rig.picker.isPending(for: frame), "a failed pass counts as landed, so nothing waits for it forever")
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == nil)
        try await rig.prepare(frame)
        await rig.picker.refresh(frame)
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)), "asked again, it is tried again")
    }

    /// A newer request replaces an older one that has not started, a resize is a view of its own, and an older view can be asked for
    /// again: nothing waits forever and nothing is answered with another view's pixels.
    @Test func aNewCameraOrSizeSupersedesOlderRequestsAndAnOlderViewCanBeAskedForAgain() async throws {
        let rig = try Rig()
        let first = RenderFixtures.boxFrame()
        var second = first
        second.pose.yaw += 0.1
        var resized = second
        resized.size = ViewportSize(width: 100, height: 100)
        try await rig.prepare(first)
        rig.picker.schedule(first)            // an orbit asks for a pass every frame ...
        rig.picker.schedule(second)           // ... and each replaces the one before while the view moves ...
        await rig.picker.refresh(resized)     // ... until a click or the quiet runs the newest
        #expect(!rig.picker.isPending(for: resized))
        #expect(rig.picker.isPending(for: first) && rig.picker.isPending(for: second), "the replaced requests never ran")
        #expect(rig.picker.pick(at: ScreenPoint(150, 150), in: resized) == nil, "outside the smaller view")
        await rig.picker.refresh(second)
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: second) == .face(solid: 0, FaceID(2)),
                "an older view can be asked for again")
    }

    @Test(.timeLimit(.minutes(1)))
    func theQuietBeforeAPassIsShortAndStartsItWithoutAnyoneAsking() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        try await rig.prepare(frame)
        rig.picker.schedule(frame)
        #expect(rig.picker.isPending(for: frame), "not yet: the view has not been still")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            rig.picker.onReady = { continuation.resume() }
        }
        #expect(!rig.picker.isPending(for: frame), "the pass ran by itself after \(SDLViewportPicker.settleDelay)")
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)))
    }

    /// `PickID` holds 256 solids (8 bits): a scene with more draws them all, and the ones past 255 are simply not pickable.
    @Test func aSolidPastTheTwoHundredFiftyFifthIsDrawnButNotPickable() async throws {
        let rig = try Rig()
        var frame = RenderFixtures.boxFrame()
        let beside = TestMeshes.box(BoundingBox(min: Vector3(-15, -10, 0), max: Vector3(-10, 10, 30)))
        frame.items.append(FrameItem(meshSerial: 2, mesh: beside, solidIndex: PickID.maxSolids, isGhost: false, hoveredFace: nil,
                                     selectedFaces: [], selectedEdges: []))
        #expect(try await rig.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)))
        #expect(rig.picker.pick(at: ScreenPoint(40, 100), in: frame) == nil, "the 257th solid has no pick ID")
        let drawn = try await rig.draw(frame)
        let alone = try await rig.draw(RenderFixtures.boxFrame())
        #expect(Rig.color(drawn, 40, 100) != Rig.color(alone, 40, 100), "but it is drawn")
    }

    @Test func anEmptySceneHasNothingUnderAnyPixel() async throws {
        let rig = try Rig()
        #expect(try await rig.pick(at: ScreenPoint(100, 100), in: RenderFixtures.emptyFrame()) == nil)
    }

    @Test func aGuideIsNeverPickedAndATintedPartIsPickedAsBefore() async throws {
        let rig = try Rig()
        let wide = TestMeshes.box(BoundingBox(min: Vector3(-15, -10, 0), max: Vector3(15, 10, 30)))
        var frame = RenderFixtures.boxFrame()
        frame.items.append(FrameItem(meshSerial: 2, mesh: wide, solidIndex: 1, isGhost: false, hoveredFace: nil,
                                     selectedFaces: [], selectedEdges: Set(wide.edgePolylines.keys), isGuide: true))
        #expect(try await rig.pick(at: ScreenPoint(25, 100), in: frame) == nil, "on the guide's edge")
        #expect(rig.picker.pick(at: ScreenPoint(40, 100), in: frame) == nil, "where the guide's face would be")
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)), "the part is picked as before")
        var tinted = RenderFixtures.boxFrame()
        tinted.items[0].fieldValues = TestMeshes.box(RenderFixtures.bounds).positions.map { Float($0.x) }
        tinted.items[0].fieldRamp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -5...5)
        #expect(try await rig.pick(at: ScreenPoint(100, 100), in: tinted) == .face(solid: 0, FaceID(2)), "the front face, as untinted")
    }

    @Test func theCutViewPicksOnlyWhatIsLeft() async throws {
        let rig = try Rig()
        func frame(_ clip: ViewportClip?) -> ViewportFrame {
            var frame = RenderFixtures.boxFrame()
            frame.clip = clip
            return frame
        }
        func nearSide(_ y: Double) -> ViewportClip { ViewportClip(origin: Vector3(0, y, 0), normal: Vector3(0, -1, 0)) }
        let point = ScreenPoint(100, 100)
        #expect(try await rig.pick(at: point, in: frame(nil)) == .face(solid: 0, FaceID(2)), "the front face")
        let inside = try await rig.pick(at: point, in: frame(nearSide(0)))
        #expect(inside == .face(solid: 0, FaceID(4)), "the back face, seen from inside: \(String(describing: inside))")
        #expect(try await rig.pick(at: point, in: frame(nearSide(100))) == nil)
    }

    @Test func twoSolidsAreToldApartByTheirIndex() async throws {
        let rig = try Rig()
        var frame = RenderFixtures.boxFrame()
        let beside = TestMeshes.box(BoundingBox(min: Vector3(-15, -10, 0), max: Vector3(-10, 10, 30)))
        frame.items.append(FrameItem(meshSerial: 2, mesh: beside, solidIndex: 1, isGhost: false, hoveredFace: nil,
                                     selectedFaces: [], selectedEdges: []))
        #expect(try await rig.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)))
        #expect(rig.picker.pick(at: ScreenPoint(40, 100), in: frame) == .face(solid: 1, FaceID(2)), "the second box is at view x 25…50")
    }
}
#endif

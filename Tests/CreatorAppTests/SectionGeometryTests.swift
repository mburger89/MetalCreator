import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Testing
@testable import CreatorApp

/// The section view's planes, clips and handle (section spec §3.1, §3.2, §3.5).
@MainActor
struct SectionGeometryTests {
    static let bounds = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))
    static let above = Vector3(0.3, 0.2, 1).normalized ?? .unitZ

    private func clip(_ settings: SectionSettings) throws -> ViewportClip {
        guard case .origin(let origin) = settings.reference else { throw SectionTestError.notOrigin }
        return SectionGeometry.clip(SectionGeometry.frame(of: origin), offset: settings.offset, isFlipped: settings.isFlipped)
    }

    @Test func anOriginPlaneStartsThroughTheCentreCuttingTheViewersSide() throws {
        let settings = SectionGeometry.starting(origin: nil, bounds: Self.bounds, toEye: Self.above)
        #expect(settings.reference == .origin(.xy) && settings.offset == 15 && !settings.isFlipped && settings.isOn)
        let cut = try clip(settings)
        #expect(cut.origin == Vector3(0, 0, 15) && cut.normal == .unitZ)
        #expect(cut.removes(Vector3(0, 0, 25)) && !cut.removes(Vector3(0, 0, 5)))
        let below = SectionGeometry.starting(origin: nil, bounds: Self.bounds, toEye: Vector3(0, 0.1, -1).normalized ?? .unitZ)
        #expect(below.isFlipped)
        #expect(try clip(below).normal == -Vector3.unitZ)
    }

    @Test func aChosenOriginPlaneIsKept() {
        let settings = SectionGeometry.starting(origin: .yz, bounds: Self.bounds, toEye: Self.above)
        #expect(settings.reference == .origin(.yz) && settings.offset == 0)
    }

    private static func face(kind: SurfaceKind, normal: Vector3?) -> FaceInfo {
        FaceInfo(id: FaceID(0), kind: kind, normal: normal, area: 100, centroid: Vector3(0, 0, 30), tags: [])
    }

    @Test func aFaceSectionGoesIntoTheMaterial() throws {
        let frame = try #require(SectionGeometry.frame(ofFace: Self.face(kind: .plane, normal: .unitZ)))
        #expect(frame.offsetDirection == -Vector3.unitZ)
        let cut = SectionGeometry.clip(frame, offset: 4, isFlipped: false)
        #expect(cut.origin == Vector3(0, 0, 26) && cut.normal == .unitZ)
        #expect(SectionGeometry.clip(frame, offset: 4, isFlipped: true).normal == -Vector3.unitZ)
    }

    @Test func aCurvedFaceHasNoFrame() {
        #expect(SectionGeometry.frame(ofFace: Self.face(kind: .cylinder, normal: .unitZ)) == nil)
        #expect(SectionGeometry.frame(ofFace: Self.face(kind: .plane, normal: nil)) == nil)
    }

    @Test func theHandleSpansThePartAndStretchesToATypedOffset() {
        let frame = SectionGeometry.frame(of: .xy)
        let handle = SectionGeometry.handle(frame, offset: 15, bounds: Self.bounds)
        #expect(handle.range == 0...30 && handle.anchor == Vector3(0, 0, 0) && handle.direction == .unitZ)
        #expect(handle.value == 15 && handle.style == .linear && handle.tint == .solid)
        #expect(SectionGeometry.handle(frame, offset: 50, bounds: Self.bounds).range == 0...50)
        #expect(SectionGeometry.handle(frame, offset: -7, bounds: Self.bounds).range == -7...30)
    }

    @Test func theHandleOfAFaceFrameRunsFromTheFaceDownThroughThePart() throws {
        let frame = try #require(SectionGeometry.frame(ofFace: Self.face(kind: .plane, normal: .unitZ)))
        let handle = SectionGeometry.handle(frame, offset: 0, bounds: Self.bounds)
        #expect(handle.anchor == Vector3(0, 0, 30) && handle.range == 0...30)
    }

    @Test func aFaceIsFoundInTheSceneByItsTags() async throws {
        let kernel = FakeKernel()
        func box() async throws -> Solid {
            try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                     tag: NodeTag(node: NodeID(), item: 0))
        }
        let (first, second, third) = (try await box(), try await box(), try await box())
        let top = try #require(second.topology.faces.first { $0.normal == .unitZ && $0.kind == .plane })
        let pick = try #require(second.topology.facePick(for: top.id))
        let hidden = [ViewportItem(solid: second, isGhost: true), ViewportItem(solid: second, isGuide: true)]
        #expect(SectionGeometry.resolveFace(pick, in: hidden + [ViewportItem(solid: first)]) == nil,
                "a ghost and a guide are no part of the scene")
        let scene = hidden + [ViewportItem(solid: first), ViewportItem(solid: second), ViewportItem(solid: third)]
        let found = SectionGeometry.resolveFace(pick, in: scene)
        #expect(found?.face == top && found?.isGuess == false)
        let stray = FacePick(tags: [TopoTag(node: NodeID(), item: 9, role: .endCap)])
        #expect(SectionGeometry.resolveFace(stray, in: [ViewportItem(solid: first)]) == nil)
    }
}

private enum SectionTestError: Error { case notOrigin }

import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Picking anchors for symbols")
struct SymbolPickTests {
    private typealias Fixtures = AnnotationFixtures
    private typealias Fixture = TopologyFixtures
    private let top = StandardOrientation.top.frame
    private let mapping = ViewMapping(scale: 2, offset: Vector2(100, 50))

    private func v(_ x: Double, _ y: Double, _ z: Double) -> Vector3 { Vector3(x, y, z) }

    private func anchor(
        _ candidate: PickCandidate, _ topology: Topology, _ purpose: PickPurpose, isometric: Bool = false
    ) -> Result<PickedAnchor, DrawingRefusal> {
        DrawingPick.anchor(
            for: candidate, click: Vector2(120, 60), purpose: purpose, topology: topology, frame: top, mapping: mapping,
            isIsometric: isometric, parts: nil)
    }

    private func refused(_ result: Result<PickedAnchor, DrawingRefusal>) -> String? {
        if case .failure(let refusal) = result { refusal.sentence } else { nil }
    }

    private func picked(_ result: Result<PickedAnchor, DrawingRefusal>) -> PickedAnchor? {
        if case .success(let found) = result { found } else { nil }
    }

    private let part = Fixtures.topology()
    private let symbolPurposes: [PickPurpose] = [.datum, .frame, .surface]

    @Test func aDatumTakesAStraightLine() throws {
        let result = try #require(picked(anchor(.edge(EdgeID(102), stroke: 0), part, .datum)))
        #expect(result.target == Fixtures.pick(part, 102))
        #expect(result.shape == .line(Vector2(0, 0), Vector2(40, 0)))
    }

    @Test func aDatumRefusesACircle() {
        let sentence = "A datum symbol stands on a straight line of a view or on a dimension."
        #expect(DrawingPick.datumCircleSentence == sentence)
        #expect(refused(anchor(.edge(EdgeID(0), stroke: 0), part, .datum)) == sentence)
    }

    @Test func aCornerPicksItsLine() throws {
        let result = try #require(picked(anchor(.corner(EdgeID(102), at: Vector2(100, 50)), part, .frame)))
        #expect(result.target == Fixtures.pick(part, 102))
    }

    @Test func aFrameTakesAFaceOnCircle() throws {
        let result = try #require(picked(anchor(.edge(EdgeID(0), stroke: 0), part, .frame)))
        #expect(result.target == Fixtures.pick(part, 0))
    }

    @Test func aFrameTakesACentreAsItsCircle() throws {
        let result = try #require(picked(anchor(.centre(EdgeID(0), at: Vector2(120, 60)), part, .frame)))
        #expect(result.target == Fixtures.pick(part, 0))
    }

    @Test func aSurfaceRefusesACircle() {
        let sentence = "A surface symbol stands on a straight line of a view."
        #expect(DrawingPick.surfaceCircleSentence == sentence)
        #expect(refused(anchor(.edge(EdgeID(0), stroke: 0), part, .surface)) == sentence)
    }

    @Test func symbolsAreRefusedInIsometricViews() {
        let sentence = "Isometric views take notes and leaders, not datum, tolerance or surface symbols."
        #expect(DrawingPick.symbolIsometricSentence == sentence)
        for purpose in symbolPurposes {
            #expect(refused(anchor(.edge(EdgeID(102), stroke: 0), part, purpose, isometric: true)) == sentence)
        }
        #expect(
            refused(anchor(.edge(EdgeID(102), stroke: 0), part, .dimension, isometric: true))
                == DrawingPick.isometricSentence)
    }

    @Test func anUnnamedEdgeIsRefused() {
        let unnamed = FaceInfo(
            id: FaceID(5), kind: .plane, normal: v(0, 0, 1), area: 1, centroid: v(0, 0, 0),
            tags: Fixture.tags(.unnamed(face: 7)))
        let topology = Fixture.plate(
            edges: [Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 5)], extraFaces: [unnamed])
        let sentence = "This edge has no lasting name, so a symbol can't hold on to it."
        #expect(DrawingPick.symbolNoEdgeNameSentence == sentence)
        for purpose in symbolPurposes { #expect(refused(anchor(.edge(EdgeID(0), stroke: 0), topology, purpose)) == sentence) }
        #expect(refused(anchor(.edge(EdgeID(0), stroke: 0), topology, .dimension)) == DrawingPick.noEdgeNameSentence)
    }

    @Test func aSharedEdgeIsRefusedInSymbolWords() {
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 1),
            Fixture.line(1, v(0, 0, 20), v(10, 0, 20), between: 0, 1),
        ])
        #expect(
            refused(anchor(.edge(EdgeID(0), stroke: 0), topology, .datum))
                == "This line's edge shares its name with other edges, so a symbol can't hold on to it.")
    }

    @Test func aSlantedEdgeIsAccepted() throws {
        let topology = Fixture.plate(edges: [Fixture.line(0, v(0, 0, 0), v(40, 0, 10), between: 0, 1)])
        for purpose in symbolPurposes {
            let result = try #require(picked(anchor(.edge(EdgeID(0), stroke: 0), topology, purpose)))
            #expect(result.shape == .line(Vector2(0, 0), Vector2(40, 0)))
        }
        #expect(refused(anchor(.edge(EdgeID(0), stroke: 0), topology, .dimension)) == DrawingPick.lineSentence)
    }

    @Test func anEndOnEdgeIsRefused() {
        let topology = Fixture.plate(edges: [Fixture.line(0, v(0, 0, 0), v(0, 0, 10), between: 0, 1)])
        let sentence = "This edge is seen end on here, so a symbol can't stand on it."
        #expect(DrawingPick.symbolEndOnSentence == sentence)
        for purpose in symbolPurposes { #expect(refused(anchor(.edge(EdgeID(0), stroke: 0), topology, purpose)) == sentence) }
    }

    @Test func aFrameRefusesASpline() {
        let spline = EdgeInfo(
            id: EdgeID(0), kind: .bspline, direction: nil, length: 10, midpoint: v(5, 0, 0), convexity: .convex,
            faces: [FaceID(0), FaceID(1)], curve: nil)
        let topology = Fixture.plate(edges: [spline])
        let sentence = "This edge isn't a straight line or a circle, so a symbol can't stand on it here."
        #expect(DrawingPick.symbolCurveSentence == sentence)
        #expect(refused(anchor(.edge(EdgeID(0), stroke: 0), topology, .frame)) == sentence)
    }

    @Test func aFrameRefusesATiltedCircle() {
        let topology = Fixture.plate(edges: [
            Fixture.circle(0, center: v(0, 0, 0), axis: v(0, 1, 0), radius: 5, between: 0, 1),
        ])
        let sentence = "This circle isn't seen face on here; point the frame at it in a view that looks along its axis."
        #expect(DrawingPick.symbolCircleSentence == sentence)
        #expect(refused(anchor(.edge(EdgeID(0), stroke: 0), topology, .frame)) == sentence)
    }

    @Test func aCylinderSeenSideOnGivesADatumOutline() throws {
        let topology = Fixture.plate(
            edges: [], extraFaces: [Fixture.cylinder(4, .side(segment: 4), axisPoint: v(0, 0, 5), axis: v(1, 0, 0), radius: 5)])
        let result = try #require(picked(anchor(.outline(FaceID(4), stroke: 0), topology, .datum)))
        guard case .outline = result.target else {
            Issue.record("not an outline")
            return
        }
        let turned = Fixture.plate(
            edges: [], extraFaces: [Fixture.cylinder(4, .side(segment: 4), axisPoint: v(0, 0, 5), axis: v(0, 0, 1), radius: 5)])
        #expect(
            refused(anchor(.outline(FaceID(4), stroke: 0), turned, .datum))
                == "This cylinder isn't seen side on, so it has no outline here for a symbol to stand on.")
    }
}

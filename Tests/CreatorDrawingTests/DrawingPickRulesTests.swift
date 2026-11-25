import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

@Suite("Picking rules")
struct DrawingPickRulesTests {
    private typealias Fixture = TopologyFixtures
    private let front = StandardOrientation.front.frame
    private let mapping = ViewMapping(scale: 2, offset: Vector2(100, 50))

    private func v(_ x: Double, _ y: Double, _ z: Double) -> Vector3 { Vector3(x, y, z) }

    private func anchor(
        _ candidate: PickCandidate, _ topology: Topology, purpose: PickPurpose = .dimension, click: Vector2 = .zero,
        isometric: Bool = false, frame: ProjectionFrame? = nil
    ) -> Result<PickedAnchor, DrawingRefusal> {
        DrawingPick.anchor(
            for: candidate, click: click, purpose: purpose, topology: topology, frame: frame ?? front, mapping: mapping,
            isIsometric: isometric)
    }

    private func refused(_ result: Result<PickedAnchor, DrawingRefusal>) -> String? {
        if case .failure(let refusal) = result { refusal.sentence } else { nil }
    }

    private func picked(_ result: Result<PickedAnchor, DrawingRefusal>) -> PickedAnchor? {
        if case .success(let anchor) = result { anchor } else { nil }
    }

    private var corner: Topology {
        Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 1),
            Fixture.line(1, v(0, 0, 0), v(0, 0, 10), between: 0, 2),
        ])
    }

    // MARK: Foreshortening and tools (R5)

    @Test func anIsometricViewRefusesDimensionsButNotLeaders() {
        let topology = corner
        #expect(
            refused(anchor(.edge(EdgeID(0), stroke: 0), topology, isometric: true))
                == "Isometric views take notes and leaders, not dimensions.")
        #expect(picked(anchor(.edge(EdgeID(0), stroke: 0), topology, purpose: .leader, isometric: true)) != nil)
    }

    @Test func aTiltedLineIsRefused() {
        let topology = Fixture.plate(edges: [Fixture.line(0, v(0, 0, 0), v(10, 5, 0), between: 0, 1)])
        #expect(
            refused(anchor(.edge(EdgeID(0), stroke: 0), topology))
                == "This edge isn't square to the view, so its length here would be foreshortened. "
                + "Dimension it in a view that sees it face on, or in an auxiliary view.")
        // A leader needs no true length.
        #expect(picked(anchor(.edge(EdgeID(0), stroke: 0), topology, purpose: .leader)) != nil)
    }

    @Test func aCircleSeenEdgeOnIsRefused() {
        let topology = Fixture.plate(edges: [Fixture.circle(0, center: v(5, 0, 5), axis: v(0, 0, 1), radius: 2, between: 0, 1)])
        #expect(
            refused(anchor(.edge(EdgeID(0), stroke: 0), topology))
                == "This circle isn't seen face on, so its size here would be foreshortened. "
                + "Dimension it in a view that looks along its axis.")
    }

    @Test func anEllipseEdgeIsRefusedForDimensionsOnly() throws {
        let ellipse = EdgeInfo(
            id: EdgeID(0), kind: .ellipse, direction: nil, length: 5, midpoint: v(1, 0, 1), convexity: .convex,
            faces: [FaceID(0), FaceID(1)], curve: nil)
        let topology = Fixture.plate(edges: [ellipse])
        #expect(
            refused(anchor(.edge(EdgeID(0), stroke: 0), topology))
                == "This edge isn't a straight line or a circle, so it can't be dimensioned here.")
        let leader = try #require(picked(anchor(.edge(EdgeID(0), stroke: 0), topology, purpose: .leader)))
        #expect(leader.shape == .point(Vector2(1, 1)))
    }

    @Test func anOutlineNeedsToBeSeenSideOn() {
        let endOn = Fixture.plate(
            edges: [], extraFaces: [Fixture.cylinder(4, .side(segment: 4), axisPoint: v(0, 0, 5), axis: v(0, 1, 0))])
        #expect(
            refused(anchor(.outline(FaceID(4), stroke: 0), endOn))
                == "This cylinder isn't seen side on, so its size here would be foreshortened.")
        let sphere = FaceInfo(
            id: FaceID(4), kind: .sphere, normal: nil, area: 1, centroid: v(0, 0, 0), tags: Fixture.tags(.side(segment: 4)))
        #expect(
            refused(anchor(.outline(FaceID(4), stroke: 0), Fixture.plate(edges: [], extraFaces: [sphere])))
                == "Only a cylinder's outline can be dimensioned here.")
    }

    // MARK: Holes

    private let top = StandardOrientation.top.frame

    private func holeFace(_ id: Int, _ kind: SurfaceKind, normal: Vector3, z: Double, radius: Double? = nil) -> FaceInfo {
        FaceInfo(
            id: FaceID(id), kind: kind, normal: normal, area: 1, centroid: v(0, 0, z), tags: Fixture.tags(.side(segment: id)),
            radius: radius, axisPoint: radius == nil ? nil : v(0, 0, 0))
    }

    private func holePart(faces: [FaceInfo], rings: [EdgeInfo]) -> Topology {
        let outer = [
            holeFace(0, .plane, normal: v(0, 0, 1), z: 0), holeFace(1, .plane, normal: v(0, 0, -1), z: -20),
            holeFace(9, .plane, normal: v(1, 0, 0), z: -10),
        ]
        let lines = [
            Fixture.line(100, v(20, 0, 0), v(20, 20, 0), between: 0, 9),
            Fixture.line(101, v(20, 0, -20), v(20, 20, -20), between: 1, 9),
        ]
        return Topology(faces: outer + faces, edges: lines + rings)
    }

    @Test func aBossIsNotAHole() throws {
        let up = v(0, 0, 1)
        let boss = holePart(
            faces: [holeFace(2, .cylinder, normal: up, z: 5, radius: 3), holeFace(3, .plane, normal: up, z: 10)],
            rings: [
                Fixture.circle(0, center: v(0, 0, 0), axis: up, radius: 3, between: 2, 0),
                Fixture.circle(1, center: v(0, 0, 10), axis: up, radius: 3, between: 2, 3),
            ])
        #expect(
            refused(anchor(.edge(EdgeID(0), stroke: 0), boss, purpose: .holeCallout, frame: top))
                == "This circle isn't the edge of a plain, counterbored or countersunk hole.")
        let through = holePart(
            faces: [holeFace(2, .cylinder, normal: up, z: -10, radius: 3)],
            rings: [
                Fixture.circle(0, center: v(0, 0, 0), axis: up, radius: 3, between: 2, 0),
                Fixture.circle(1, center: v(0, 0, -20), axis: up, radius: 3, between: 2, 1),
            ])
        #expect(picked(anchor(.edge(EdgeID(0), stroke: 0), through, purpose: .holeCallout, frame: top)) != nil)
        // A line is no hole; a centre mark takes any face-on circle, hole or boss.
        #expect(refused(anchor(.edge(EdgeID(100), stroke: 0), through, purpose: .holeCallout, frame: top)) != nil)
        #expect(picked(anchor(.edge(EdgeID(0), stroke: 0), boss, purpose: .centreMark, frame: top)) != nil)
        #expect(refused(anchor(.edge(EdgeID(100), stroke: 0), through, purpose: .centreMark, frame: top)) != nil)
    }
}

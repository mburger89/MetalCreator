import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

/// Hole callouts read from hand-built topologies (plan R12): a hole runs down from z = 0 along -z, its mouth in a top plane.
@Suite("Hole reading")
struct HoleReaderTests {
    typealias Fixture = TopologyFixtures
    let top = StandardOrientation.top.frame
    let up = Vector3(0, 0, 1)

    func v(_ z: Double) -> Vector3 { Vector3(0, 0, z) }

    func face(_ id: Int, _ kind: SurfaceKind, normal: Vector3, z: Double, radius: Double? = nil) -> FaceInfo {
        FaceInfo(
            id: FaceID(id), kind: kind, normal: normal, area: 1, centroid: v(z), tags: Fixture.tags(.side(segment: id)),
            radius: radius, axisPoint: radius == nil ? nil : v(0))
    }

    func ring(_ id: Int, z: Double, radius: Double, _ a: Int, _ b: Int) -> EdgeInfo {
        Fixture.circle(id, center: v(z), axis: up, radius: radius, between: a, b)
    }

    /// The part's top face (0, with a boundary line so it is no bare disc) and bottom face (1, likewise) at z = -20.
    func part(faces: [FaceInfo], edges: [EdgeInfo]) -> Topology {
        let outer = [
            face(0, .plane, normal: up, z: 0), face(1, .plane, normal: Vector3(0, 0, -1), z: -20),
            face(9, .plane, normal: Vector3(1, 0, 0), z: -10),
        ]
        let lines = [
            Fixture.line(100, Vector3(20, 0, 0), Vector3(20, 20, 0), between: 0, 9),
            Fixture.line(101, Vector3(20, 0, -20), Vector3(20, 20, -20), between: 1, 9),
        ]
        return Topology(faces: outer + faces, edges: lines + edges)
    }

    func read(_ topology: Topology, edge id: Int, frame: ProjectionFrame? = nil) -> HoleReading {
        let pick = Fixture.pick(topology, [id])
        return HoleReader.read(.edge(pick), in: topology, frame: frame ?? top, parts: [])
    }

    func shape(_ reading: HoleReading) -> HoleShape? {
        if case .hole(let shape, _, _, _) = reading { shape } else { nil }
    }

    private var through: Topology {
        part(
            faces: [face(2, .cylinder, normal: up, z: -10, radius: 3)],
            edges: [ring(0, z: 0, radius: 3, 2, 0), ring(1, z: -20, radius: 3, 2, 1)])
    }

    @Test func aThroughHole() {
        let reading = read(through, edge: 0)
        #expect(shape(reading) == HoleShape(diameter: 6))
        guard case .hole(_, let center, _, let radius) = reading else { return }
        #expect(center == v(0) && radius == 3)
    }

    @Test func aBlindFlatHole() {
        let topology = part(
            faces: [face(2, .cylinder, normal: up, z: -5, radius: 3), face(3, .plane, normal: up, z: -10)],
            edges: [ring(0, z: 0, radius: 3, 2, 0), ring(1, z: -10, radius: 3, 2, 3)])
        #expect(shape(read(topology, edge: 0)) == HoleShape(diameter: 6, depth: 10))
    }

    @Test func aDrillPoint() {
        let topology = part(
            faces: [face(2, .cylinder, normal: up, z: -5, radius: 3), face(3, .cone, normal: up, z: -10.9)],
            edges: [ring(0, z: 0, radius: 3, 2, 0), ring(1, z: -10, radius: 3, 2, 3)])
        #expect(shape(read(topology, edge: 0)) == HoleShape(diameter: 6, depth: 10))
    }

    private var counterbore: Topology {
        part(
            faces: [
                face(2, .cylinder, normal: up, z: -3, radius: 5.5), face(3, .plane, normal: up, z: -6),
                face(4, .cylinder, normal: up, z: -13, radius: 3),
            ],
            edges: [
                ring(0, z: 0, radius: 5.5, 2, 0), ring(1, z: -6, radius: 5.5, 2, 3), ring(2, z: -6, radius: 3, 3, 4),
                ring(3, z: -20, radius: 3, 4, 1),
            ])
    }

    @Test func aCounterbore() {
        let expected = HoleShape(diameter: 6, counterbore: .init(diameter: 11, depth: 6))
        #expect(shape(read(counterbore, edge: 0)) == expected)
    }

    @Test func pickingTheInnerCircleWalksOutToTheMouth() {
        let outer = read(counterbore, edge: 0)
        let inner = read(counterbore, edge: 2)
        #expect(shape(inner) == shape(outer))
        guard case .hole(_, _, _, let radius) = inner else {
            Issue.record("expected a hole")
            return
        }
        #expect(radius == 3)
    }

    @Test func aCountersink() {
        let topology = part(
            faces: [face(2, .cone, normal: up, z: -1.5), face(3, .cylinder, normal: up, z: -11.5, radius: 3)],
            edges: [ring(0, z: 0, radius: 6, 2, 0), ring(1, z: -3, radius: 3, 2, 3), ring(2, z: -20, radius: 3, 3, 1)])
        guard let found = shape(read(topology, edge: 0)) else {
            Issue.record("expected a hole")
            return
        }
        #expect(found.diameter == 6 && found.depth == nil && found.counterbore == nil)
        #expect(found.countersink?.diameter == 12)
        #expect(abs((found.countersink?.angle ?? 0) - .pi / 2) < 1e-9)
    }

    @Test func aCircleOnABossIsNotAHole() {
        // A boss rises from the top face: its wall lies on the plane's outward side, and its own top is a bare disc.
        let topology = part(
            faces: [face(2, .cylinder, normal: up, z: 5, radius: 3), face(3, .plane, normal: up, z: 10)],
            edges: [ring(0, z: 0, radius: 3, 2, 0), ring(1, z: 10, radius: 3, 2, 3)])
        #expect(read(topology, edge: 0) == .notAHole)
        #expect(read(topology, edge: 1) == .notAHole)
    }

    /// A round part: its top face (0) is an annulus out to a larger coaxial circle on the outer cylinder (9) going down.
    private func roundPart(faces: [FaceInfo], edges: [EdgeInfo]) -> Topology {
        let outer = [
            face(0, .plane, normal: up, z: 0), face(1, .plane, normal: Vector3(0, 0, -1), z: -20),
            face(9, .cylinder, normal: up, z: -10, radius: 20),
        ]
        let rim = [ring(100, z: 0, radius: 20, 9, 0), ring(101, z: -20, radius: 20, 9, 1)]
        return Topology(faces: outer + faces, edges: rim + edges)
    }

    @Test func aHoleOnTheAxisOfARoundPart() {
        let topology = roundPart(
            faces: [face(2, .cylinder, normal: up, z: -10, radius: 3)],
            edges: [ring(0, z: 0, radius: 3, 2, 0), ring(1, z: -20, radius: 3, 2, 1)])
        #expect(shape(read(topology, edge: 0)) == HoleShape(diameter: 6))
    }

    @Test func aCounterboreOnTheAxisOfARoundPart() {
        let topology = roundPart(
            faces: [
                face(2, .cylinder, normal: up, z: -3, radius: 5.5), face(3, .plane, normal: up, z: -6),
                face(4, .cylinder, normal: up, z: -13, radius: 3),
            ],
            edges: [
                ring(0, z: 0, radius: 5.5, 2, 0), ring(1, z: -6, radius: 5.5, 2, 3), ring(2, z: -6, radius: 3, 3, 4),
                ring(3, z: -20, radius: 3, 4, 1),
            ])
        let expected = HoleShape(diameter: 6, counterbore: .init(diameter: 11, depth: 6))
        #expect(shape(read(topology, edge: 0)) == expected)
        #expect(shape(read(topology, edge: 2)) == expected)
    }

    @Test func aQuarterArcCornerIsNotAHole() {
        let topology = part(
            faces: [face(2, .cylinder, normal: up, z: -10, radius: 3)],
            edges: [
                Fixture.circle(0, center: v(0), axis: up, radius: 3, sweep: .pi / 2, between: 2, 0),
                Fixture.circle(1, center: v(-20), axis: up, radius: 3, sweep: .pi / 2, between: 2, 1),
            ])
        #expect(read(topology, edge: 0) == .notAHole)
    }

    @Test func aSlotEndIsNotAHole() {
        let topology = part(
            faces: [face(2, .cylinder, normal: up, z: -10, radius: 3)],
            edges: [
                Fixture.circle(0, center: v(0), axis: up, radius: 3, sweep: .pi, between: 2, 0),
                Fixture.circle(1, center: v(-20), axis: up, radius: 3, sweep: .pi, between: 2, 1),
            ])
        #expect(read(topology, edge: 0) == .notAHole)
    }

    @Test func theOutwardNormalAloneRefusesAWallOnTheOutwardSide() {
        // Rings and a far end below the mouth would read as a hole, but the wall's centroid lies on the plane's outward side.
        let topology = part(
            faces: [face(2, .cylinder, normal: up, z: 10, radius: 3)],
            edges: [ring(0, z: 0, radius: 3, 2, 0), ring(1, z: -20, radius: 3, 2, 1)])
        #expect(read(topology, edge: 0) == .notAHole)
    }

    @Test func aBlindCounterbore() {
        let topology = part(
            faces: [
                face(2, .cylinder, normal: up, z: -3, radius: 5.5), face(3, .plane, normal: up, z: -6),
                face(4, .cylinder, normal: up, z: -11, radius: 3), face(5, .plane, normal: up, z: -16),
            ],
            edges: [
                ring(0, z: 0, radius: 5.5, 2, 0), ring(1, z: -6, radius: 5.5, 2, 3), ring(2, z: -6, radius: 3, 3, 4),
                ring(3, z: -16, radius: 3, 4, 5),
            ])
        #expect(shape(read(topology, edge: 0)) == HoleShape(diameter: 6, depth: 10, counterbore: .init(diameter: 11, depth: 6)))
    }

    @Test func aCircleSeenEdgeOnIsForeshortened() {
        #expect(read(through, edge: 0, frame: StandardOrientation.front.frame) == .lost(.foreshortened))
    }

    @Test func anUnknownStackIsNotAHole() {
        let topology = part(
            faces: [
                face(2, .cylinder, normal: up, z: -3, radius: 5.5), face(3, .plane, normal: up, z: -6),
                face(4, .cone, normal: up, z: -13),
            ],
            edges: [
                ring(0, z: 0, radius: 5.5, 2, 0), ring(1, z: -6, radius: 5.5, 2, 3), ring(2, z: -6, radius: 3, 3, 4),
                ring(3, z: -20, radius: 1, 4, 1),
            ])
        #expect(read(topology, edge: 0) == .notAHole)
    }

    @Test func aFilletedCounterboreFloorIsNotReadAsAPlainHole() {
        // The floor's outer circle borders a torus that rises: a step that is no wall, so the stack is unknown.
        let topology = part(
            faces: [
                face(2, .torus, normal: up, z: -3), face(3, .plane, normal: up, z: -6),
                face(4, .cylinder, normal: up, z: -13, radius: 3),
            ],
            edges: [
                ring(0, z: 0, radius: 5.5, 2, 0), ring(1, z: -6, radius: 5.5, 2, 3), ring(2, z: -6, radius: 3, 3, 4),
                ring(3, z: -20, radius: 3, 4, 1),
            ])
        #expect(read(topology, edge: 2) == .notAHole)
    }

    @Test func aRisingWallWithNoFarCircleIsNotAHole() {
        // A counterbore that breaks out through a side face: its top edge is no circle.
        let topology = part(
            faces: [
                face(2, .cylinder, normal: up, z: -3, radius: 5.5), face(3, .plane, normal: up, z: -6),
                face(4, .cylinder, normal: up, z: -13, radius: 3),
            ],
            edges: [ring(1, z: -6, radius: 5.5, 2, 3), ring(2, z: -6, radius: 3, 3, 4), ring(3, z: -20, radius: 3, 4, 1)])
        #expect(read(topology, edge: 2) == .notAHole)
    }

    @Test func aLostEdgeIsItsReason() {
        let topology = through
        let pick = Fixture.pick(topology, [0])
        let gone = Topology(faces: topology.faces, edges: [])
        #expect(HoleReader.read(.edge(pick), in: gone, frame: top, parts: []) == .lost(.missing))
    }
}

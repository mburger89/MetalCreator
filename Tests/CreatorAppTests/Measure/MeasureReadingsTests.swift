import Foundation
import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorApp

struct MeasureReadingsTests {
    private func values(_ picks: [MeasurePick], _ topologies: [Int: Topology]) -> [MeasureQuantity: Double] {
        Dictionary(MeasureReadings.readings(for: picks, topologies: topologies).map { ($0.quantity, $0.value) },
                   uniquingKeysWith: { first, _ in first })
    }

    @Test func anArcGivesRadiusAndDiameter() {
        let topology = MeasureFixtures.topology(edges: [MeasureFixtures.circle(0, radius: 3, sweep: .pi)])
        let result = values([.edge(solid: 0, EdgeID(0))], topology)
        #expect(result[.radius] == 3 && result[.diameter] == 6)
    }

    @Test func aCylinderGivesRadiusAndDiameter() {
        let topology = MeasureFixtures.topology(faces: [MeasureFixtures.face(0, .cylinder, normal: .unitZ, radius: 4, axisPoint: .zero)])
        let result = values([.face(solid: 0, FaceID(0))], topology)
        #expect(result[.radius] == 4 && result[.diameter] == 8)
    }

    @Test func aStraightEdgeGivesItsLength() {
        let topology = MeasureFixtures.topology(edges: [MeasureFixtures.line(0, from: .zero, to: Vector3(3, 4, 0))])
        #expect(values([.edge(solid: 0, EdgeID(0))], topology)[.length] == 5)
    }

    @Test func aFaceGivesItsAreaAndACornerItsPosition() {
        let topology = MeasureFixtures.topology(faces: [MeasureFixtures.face(0, normal: .unitZ, area: 12)])
        #expect(values([.face(solid: 0, FaceID(0))], topology)[.area] == 12)
        let corner = MeasurePick.corner(solid: 0, EdgeID(0), .start, at: Vector3(1, 2, 3))
        let readings = MeasureReadings.readings(for: [corner], topologies: topology)
        #expect(readings == [MeasureReading(quantity: .position, value: 0, point: Vector3(1, 2, 3))])
    }

    @Test func facesAngles() {
        let topology = MeasureFixtures.topology(faces: [
            MeasureFixtures.face(0, normal: .unitZ), MeasureFixtures.face(1, normal: .unitX),
            MeasureFixtures.face(2, normal: Vector3(0, 0, -1)),
        ])
        let a = MeasurePick.face(solid: 0, FaceID(0))
        let perpendicular = values([a, .face(solid: 0, FaceID(1))], topology)[.angle] ?? -1
        #expect(abs(perpendicular - 90) < 1e-9)
        #expect(abs(values([a, .face(solid: 0, FaceID(2))], topology)[.angle] ?? -1) < 1e-9)
    }

    @Test func anEdgeAgainstAFace() {
        let direction = Vector3(cos(Double.pi / 6), 0, sin(Double.pi / 6))
        let topology = MeasureFixtures.topology(faces: [MeasureFixtures.face(0, normal: .unitZ)],
                                                edges: [MeasureFixtures.line(0, from: .zero, to: direction * 5)])
        let angle = values([.edge(solid: 0, EdgeID(0)), .face(solid: 0, FaceID(0))], topology)[.angle] ?? -1
        #expect(abs(angle - 30) < 1e-9)
    }

    @Test func twoEdgesAtOneHundredThirtyFiveDegreesGive45() {
        let second = Vector3(cos(3 * Double.pi / 4), sin(3 * Double.pi / 4), 0)
        let topology = MeasureFixtures.topology(edges: [MeasureFixtures.line(0, from: .zero, to: Vector3(1, 0, 0)),
                                                        MeasureFixtures.line(1, from: .zero, to: second),
    ])
        let angle = values([.edge(solid: 0, EdgeID(0)), .edge(solid: 0, EdgeID(1))], topology)[.angle] ?? -1
        #expect(abs(angle - 45) < 1e-9)
    }

    @Test func parallelCylindersGiveACentreDistance() {
        let topology = MeasureFixtures.topology(faces: [
            MeasureFixtures.face(0, .cylinder, normal: .unitZ, radius: 2, axisPoint: .zero),
            MeasureFixtures.face(1, .cylinder, normal: .unitZ, radius: 2, axisPoint: Vector3(12, 16, 7)),
            MeasureFixtures.face(2, .cylinder, normal: .unitX, radius: 2, axisPoint: Vector3(0, 0, 9)),
        ])
        let a = MeasurePick.face(solid: 0, FaceID(0))
        #expect(values([a, .face(solid: 0, FaceID(1))], topology)[.centreDistance] == 20)
        #expect(values([a, .face(solid: 0, FaceID(2))], topology)[.centreDistance] == nil)
    }

    @Test func aCornerAndAFaceHaveNoAngle() {
        let topology = MeasureFixtures.topology(faces: [MeasureFixtures.face(0, normal: .unitZ)])
        let corner = MeasurePick.corner(solid: 0, EdgeID(0), .end, at: .zero)
        #expect(values([corner, .face(solid: 0, FaceID(0))], topology)[.angle] == nil)
    }
}

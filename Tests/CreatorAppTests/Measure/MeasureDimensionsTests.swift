import CreatorGeometry
import CreatorKernel
import CreatorViewport
import Testing

@testable import CreatorApp

struct MeasureDimensionsTests {
    private let style = DimensionStyle.ansi
    private let units = DocumentUnits()

    private func make(_ picks: [MeasurePick], _ topologies: [Int: Topology], distance: ShapeDistance? = nil) -> [OverlayDimension] {
        let readings = MeasureReadings.readings(for: picks, topologies: topologies)
        return MeasureDimensions.dimensions(for: picks, readings: readings, distance: distance, topologies: topologies,
                                            style: style, units: units)
    }

    @Test func aDistanceIsOneLinearDimension() {
        let found = ShapeDistance(distance: 40, from: .zero, to: Vector3(40, 0, 0))
        let made = make([], [:], distance: found)
        #expect(made.count == 1)
        #expect(made[0].text == style.text(DimensionReading(40, .length), units: units))
        guard case let .linear(from, to, _, _, _) = made[0].geometry else { Issue.record("not linear"); return }
        #expect(from == .zero && to == Vector3(40, 0, 0))
        #expect(made[0].tint == .dimensionReference)
    }

    @Test func aZeroDistanceDrawsNoDimension() {
        #expect(make([], [:], distance: ShapeDistance(distance: 0, from: .zero, to: .zero)).isEmpty)
    }

    @Test func anArcIsRadialWithRAndACircleWithDiameter() {
        let topology = MeasureFixtures.topology(edges: [MeasureFixtures.circle(0, radius: 3, sweep: .pi),
                                                        MeasureFixtures.circle(1, radius: 3, sweep: 2 * .pi),
    ])
        let arc = make([.edge(solid: 0, EdgeID(0))], topology)
        let full = make([.edge(solid: 0, EdgeID(1))], topology)
        #expect(arc.count == 1 && arc[0].text.hasPrefix("R"))
        #expect(full.count == 1 && full[0].text.hasPrefix("\u{D8}"))
        guard case .radial = arc[0].geometry else { Issue.record("not radial"); return }
    }

    @Test func aCylinderIsDiametral() {
        let topology = MeasureFixtures.topology(faces: [
                                                    MeasureFixtures.face(0, .cylinder, normal: .unitZ, radius: 4, axisPoint: .zero,
                                                    centroid: Vector3(4, 0, 5)),
        ])
        let made = make([.face(solid: 0, FaceID(0))], topology)
        #expect(made.count == 1 && made[0].text.hasPrefix("\u{D8}"))
    }

    @Test func aStraightEdgeAloneIsLinearAlongIt() {
        let topology = MeasureFixtures.topology(edges: [MeasureFixtures.line(0, from: .zero, to: Vector3(0, 7, 0))])
        let made = make([.edge(solid: 0, EdgeID(0))], topology)
        guard made.count == 1, case let .linear(from, to, direction, side, _) = made[0].geometry else {
            Issue.record("expected one linear"); return
        }
        #expect(from == .zero && to == Vector3(0, 7, 0) && direction == .unitY && abs(side.dot(direction)) < 1e-9)
    }

    @Test func anAngleOnlyForNonParallelFaces() {
        let topology = MeasureFixtures.topology(faces: [
                                                    MeasureFixtures.face(0, normal: .unitZ), MeasureFixtures.face(1, normal: .unitX),
                                                    MeasureFixtures.face(2, normal: .unitZ),
    ])
        let found = ShapeDistance(distance: 3, from: .zero, to: Vector3(0, 0, 3))
        let perpendicular = make([.face(solid: 0, FaceID(0)), .face(solid: 0, FaceID(1))], topology, distance: found)
        let parallel = make([.face(solid: 0, FaceID(0)), .face(solid: 0, FaceID(2))], topology, distance: found)
        let angular = perpendicular.compactMap { dimension -> Vector3? in
            if case let .angular(vertex, _, _, _, _) = dimension.geometry { vertex } else { nil }
        }
        #expect(angular == [Vector3(0, 0, 1.5)])
        #expect(parallel.count == 1)
        #expect(Set(perpendicular.map(\.id)).count == perpendicular.count)
        #expect(perpendicular.allSatisfy { $0.id.rawValue.hasPrefix("measure/") })
    }
}

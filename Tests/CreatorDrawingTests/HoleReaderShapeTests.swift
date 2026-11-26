import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

/// Hole reading's split circles, stepped bores and non-finite sizes (plans R5, R6 and DR-4), on `HoleReaderTests`' fixtures.
extension HoleReaderTests {
    /// A full circle split into two arcs of half a turn each, OCCT's way with a hole made of two arcs (plan R6).
    private func splitRing(_ id: Int, z: Double, radius: Double, _ a: Int, _ b: Int) -> [EdgeInfo] {
        let center = v(z)
        return [0.0, Double.pi].enumerated().map { index, turn in
            let start = center + Vector3(cos(turn), sin(turn), 0) * radius
            return EdgeInfo(
                id: EdgeID(id + index), kind: .circle, direction: up, length: radius * .pi, midpoint: center, convexity: .convex,
                faces: [FaceID(a), FaceID(b)], curve: .circle(center: center, axis: up, radius: radius, start: start, sweep: .pi))
        }
    }

    @Test func aFullCircleSplitIntoTwoArcsIsOneHole() {
        let topology = part(
            faces: [face(2, .cylinder, normal: up, z: -10, radius: 3)],
            edges: splitRing(10, z: 0, radius: 3, 2, 0) + splitRing(20, z: -20, radius: 3, 2, 1))
        let reading = read(topology, edge: 10)
        #expect(shape(reading) == HoleShape(diameter: 6))
        #expect(shape(read(topology, edge: 11)) == HoleShape(diameter: 6))
        guard case .hole(_, let center, _, let radius) = reading else { return }
        #expect(center == v(0) && radius == 3)
    }

    @Test func twoArcsThatDoNotCloseTheCircleAreNotAHole() {
        let all = splitRing(10, z: 0, radius: 3, 2, 0)
        let topology = part(
            faces: [face(2, .cylinder, normal: up, z: -10, radius: 3)],
            edges: [all[0]] + splitRing(20, z: -20, radius: 3, 2, 1))
        #expect(read(topology, edge: 10) == .notAHole)
    }

    /// A counterbore of 11 mm for 6, then a 6 mm bore that steps in to 4 mm and ends on a floor at z = -16.
    private func steppedBlind(floor: Bool) -> Topology {
        var faces = [
            face(2, .cylinder, normal: up, z: -3, radius: 5.5), face(3, .plane, normal: up, z: -6),
            face(4, .cylinder, normal: up, z: -9, radius: 3), face(5, .plane, normal: up, z: -12),
            face(6, .cylinder, normal: up, z: -14, radius: 2),
        ]
        var edges = [
            ring(0, z: 0, radius: 5.5, 2, 0), ring(1, z: -6, radius: 5.5, 2, 3), ring(2, z: -6, radius: 3, 3, 4),
            ring(3, z: -12, radius: 3, 4, 5), ring(4, z: -12, radius: 2, 5, 6),
        ]
        if floor {
            faces.append(face(7, .plane, normal: up, z: -16))
            edges.append(ring(5, z: -16, radius: 2, 6, 7))
        } else {
            edges.append(ring(5, z: -20, radius: 2, 6, 1))
        }
        return part(faces: faces, edges: edges)
    }

    @Test func aSteppedBlindHoleIsBlindToTheDeepestFloor() {
        let expected = HoleShape(diameter: 6, depth: 10, counterbore: .init(diameter: 11, depth: 6))
        #expect(shape(read(steppedBlind(floor: true), edge: 0)) == expected)
    }

    @Test func aSteppedHoleThatLeavesThePartIsThrough() {
        let expected = HoleShape(diameter: 6, counterbore: .init(diameter: 11, depth: 6))
        #expect(shape(read(steppedBlind(floor: false), edge: 0)) == expected)
    }

    @Test func aHoleWithNoFiniteSizeIsLostInItsCallout() throws {
        // A bore whose diameter overflows: the callout is lost in words, never drawn as "Ø0" or "Ø inf".
        let topology = part(
            faces: [face(2, .cylinder, normal: up, z: -10, radius: 1e308)],
            edges: [ring(0, z: 0, radius: 1e308, 2, 0), ring(1, z: -20, radius: 1e308, 2, 1)])
        let callout = HoleCallout(
            anchor: .edge(Fixture.pick(topology, [0])), placement: DimensionPlacement(offset: 10, angle: 0))
        let format = NumberFormat(units: .millimetres, standard: .iso, decimalSign: .point)
        let evaluated = try #require(
            AnnotationEvaluator.evaluate(
                DrawingAnnotation(view: ViewID(), kind: .holeCallout(callout)), topology: topology, frame: top, format: format, parts: []))
        guard case .failure(let reason) = evaluated.outcome else {
            Issue.record("expected a lost callout, got \(evaluated.outcome)")
            return
        }
        #expect(reason == .refused(AnnotationEvaluator.nonFiniteSentence))
    }
}

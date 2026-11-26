#if canImport(CreatorOCCT)
import CreatorDrawing
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorOCCT

/// Holes read from real solids (plan R12): a 40 x 40 x 20 box minus a revolved stepped profile, each read from the Top view's picked
/// mouth circle.
struct HoleReaderOCCTTests {
    private let kernel = OCCTKernel()
    private let top = StandardOrientation.top.frame

    private func tag() -> NodeTag { NodeTag(node: NodeID(), item: 0) }

    /// The block with a hole cut from the points of `profile` (x = radius, y = height; the axis is the box's centre line).
    private func block(_ profile: [(Double, Double)], round: Bool = false) async throws -> Solid {
        let box: Solid
        if round {
            box = try await kernel.revolve(
                Profile2D(plane: .xz, segments: [
                    .line(Vector2(0, 0), Vector2(20, 0)), .line(Vector2(20, 0), Vector2(20, 20)),
                    .line(Vector2(20, 20), Vector2(0, 20)), .line(Vector2(0, 20), Vector2(0, 0)),
                ]), axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)), angle: Angle(radians: 2 * .pi), tag: tag())
        } else {
            box = try await kernel.extrude(
                .rectangle(width: 40, height: 40, plane: .xy), distance: 20, mode: .oneSided, tag: tag())
        }
        var segments: [Segment2D] = []
        for index in profile.indices {
            let next = profile[(index + 1) % profile.count]
            segments.append(.line(Vector2(profile[index].0, profile[index].1), Vector2(next.0, next.1)))
        }
        let cutter = try await kernel.revolve(
            Profile2D(plane: .xz, segments: segments), axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)),
            angle: Angle(radians: 2 * .pi), tag: tag())
        return try await kernel.boolean(.subtract, box, [cutter], tag: tag())
    }

    /// The circle edge of `radius` at height `z`, as a pick.
    private func read(_ solid: Solid, radius: Double, z: Double) throws -> HoleReading {
        let topology = solid.topology
        let circle = try #require(topology.edges.first { edge in
            guard case .circle(let center, _, let found, _, _)? = edge.curve else { return false }
            return abs(found - radius) < 1e-6 && abs(center.z - z) < 1e-6
        })
        let pick = try #require(topology.picks(for: [circle.id]).first)
        return HoleReader.read(.edge(pick), in: topology, frame: top, parts: [])
    }

    private func expect(_ reading: HoleReading, diameter: Double, depth: Double?, counterbore: (Double, Double)? = nil,
                        countersink: (Double, Double)? = nil) {
        guard case .hole(let shape, _, _, _) = reading else {
            Issue.record("expected a hole, got \(reading)")
            return
        }
        #expect(abs(shape.diameter - diameter) < 1e-6)
        #expect(shape.depth == nil ? depth == nil : abs(shape.depth! - (depth ?? .nan)) < 1e-6)
        let bore = counterbore ?? (.nan, .nan)
        #expect(shape.counterbore.map { abs($0.diameter - bore.0) < 1e-6 && abs($0.depth - bore.1) < 1e-6 }
            == (counterbore == nil ? nil : true))
        let sink = countersink ?? (.nan, .nan)
        #expect(shape.countersink.map { abs($0.diameter - sink.0) < 1e-6 && abs($0.angle - sink.1) < 1e-9 }
            == (countersink == nil ? nil : true))
    }

    @Test func occtCounterbore() async throws {
        let solid = try await block([(0, 21), (5.5, 21), (5.5, 14), (3, 14), (3, -1), (0, -1)])
        expect(try read(solid, radius: 5.5, z: 20), diameter: 6, depth: nil, counterbore: (11, 6))
        // The inner circle on the floor reads the same.
        expect(try read(solid, radius: 3, z: 14), diameter: 6, depth: nil, counterbore: (11, 6))
    }

    @Test func occtBlindCounterbore() async throws {
        let solid = try await block([(0, 21), (5.5, 21), (5.5, 14), (3, 14), (3, 4), (0, 4)])
        expect(try read(solid, radius: 5.5, z: 20), diameter: 6, depth: 10, counterbore: (11, 6))
    }

    @Test func occtHoleOnARoundPart() async throws {
        let solid = try await block([(0, 21), (3, 21), (3, -1), (0, -1)], round: true)
        expect(try read(solid, radius: 3, z: 20), diameter: 6, depth: nil)
    }

    @Test func occtCounterboreOnARoundPart() async throws {
        let solid = try await block([(0, 21), (5.5, 21), (5.5, 14), (3, 14), (3, -1), (0, -1)], round: true)
        expect(try read(solid, radius: 5.5, z: 20), diameter: 6, depth: nil, counterbore: (11, 6))
        expect(try read(solid, radius: 3, z: 14), diameter: 6, depth: nil, counterbore: (11, 6))
    }

    @Test func occtCountersink() async throws {
        let solid = try await block([(0, 21), (7, 21), (3, 17), (3, -1), (0, -1)])
        expect(try read(solid, radius: 6, z: 20), diameter: 6, depth: nil, countersink: (12, .pi / 2))
    }

    @Test func occtBlindDrillPoint() async throws {
        let apex = 10 - 3 / tan(59.0 * .pi / 180)
        let solid = try await block([(0, 21), (3, 21), (3, 10), (0, apex)])
        expect(try read(solid, radius: 3, z: 20), diameter: 6, depth: 10)
    }
}
#endif

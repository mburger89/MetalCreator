import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// S4: every line and circle edge carries its exact curve, which the Sketch node projects.
struct EdgeCurveTests {
    func near(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length <= 1e-9 }

    /// `point` turned about the axis through `center` along unit `axis` by `angle` radians (Rodrigues).
    func rotated(_ point: Vector3, about center: Vector3, axis: Vector3, by angle: Double) -> Vector3 {
        let v = point - center
        let turned = v * cos(angle) + axis.cross(v) * sin(angle) + axis * (axis.dot(v) * (1 - cos(angle)))
        return center + turned
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aBoxEdgeCarriesItsLineEnds(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let solid = try await box(under.make(), 10, 20, 30, tag: tag)
        let edge = try #require(edges(solid, between: { hasTag($0, .endCap, of: tag) },
                                      and: { hasTag($0, .side(segment: 0), of: tag) }).first)
        guard case .line(let start, let end)? = edge.curve else {
            Issue.record("expected a line, got \(String(describing: edge.curve))")
            return
        }
        let ends = [start, end].sorted { $0.x < $1.x }
        #expect(near(ends[0], Vector3(-5, -10, 30)) && near(ends[1], Vector3(5, -10, 30)))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aCircularRimCarriesItsCentreRadiusAndFullSweep(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let solid = try await under.make().extrude(.circle(radius: 3, center: Vector2(1, 2), plane: .xy), distance: 4,
                                                   mode: .oneSided, tag: tag)
        let rim = try #require(edges(solid, between: { hasTag($0, .endCap, of: tag) },
                                     and: { hasTag($0, .side(segment: 0), of: tag) }).first)
        guard case .circle(let center, let axis, let radius, let start, let sweep)? = rim.curve else {
            Issue.record("expected a circle, got \(String(describing: rim.curve))")
            return
        }
        #expect(near(center, Vector3(1, 2, 4)))
        #expect(isClose(abs(axis.dot(.unitZ)), 1))
        #expect(isClose(radius, 3))
        #expect(isClose((start - center).length, 3))
        #expect(isClose(sweep, 2 * .pi))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aCornerArcRunsCounterClockwiseAboutItsAxisFromItsStart(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let profile = Profile2D.roundedRectangle(width: 20, height: 10, radius: 2, plane: .xy)
        let solid = try await under.make().extrude(profile, distance: 1, mode: .oneSided, tag: tag)
        let corner = try #require(edges(solid, between: { hasTag($0, .endCap, of: tag) },
                                        and: { hasTag($0, .side(segment: 1), of: tag) }).first)
        guard case .circle(let center, let axis, let radius, let start, let sweep)? = corner.curve,
              let unit = axis.normalized else {
            Issue.record("expected a circle, got \(String(describing: corner.curve))")
            return
        }
        #expect(near(center, Vector3(8, -3, 1)))
        #expect(isClose(radius, 2))
        #expect(isClose(sweep, .pi / 2))
        // Half the sweep on from `start` is the edge's midpoint, whichever way OCCT oriented the circle.
        #expect(near(rotated(start, about: center, axis: unit, by: sweep / 2), corner.midpoint))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func everyLineAndCircleEdgeOfAHoledPlateHasACurve(_ under: KernelUnderTest) async throws {
        let plate = Profile2D(plane: .xy, outer: Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments,
                              holes: [Profile2D.circle(radius: 2, center: Vector2(1, 1), plane: .xy).segments])
        let solid = try await under.make().extrude(plate, distance: 3, mode: .oneSided, tag: newTag())
        let lineOrCircle = solid.topology.edges.filter { $0.kind == .line || $0.kind == .circle }
        #expect(!lineOrCircle.isEmpty)
        #expect(lineOrCircle.allSatisfy { $0.curve != nil })
    }
}

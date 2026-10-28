import Foundation
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// Fillet and Chamfer dimension the first edge of their set (spec §3.1, DIM-3 Task 7).
struct FeatureDimensionTests {
    /// A 20 × 10 × 10 box with every edge selected, feeding `feature`.
    func allEdgesOfABox(_ h: inout Harness, into feature: any NodeDefinition.Type,
                        _ values: [SocketName: ConstantValue]) -> Node {
        let box = h.box(20, 10, 10)
        let all = h.add(AllEdgesNode.self)
        h.wire(box, "solid", to: all, "solid")
        let node = h.add(feature, values)
        h.wire(all, "edges", to: node, "edges")
        return node
    }

    #if canImport(CreatorOCCT)
    @Test func aFilletDimensionsItsRadiusOnTheFirstEdgeWithACount() async throws {
        var h = Harness()
        let fillet = allEdgesOfABox(&h, into: FilletNode.self, ["radius": .number(1)])
        let report = try await h.run([fillet], kernel: OCCTKernel())
        let specs = try #require(report.results[fillet.id]?.dimensions)
        let spec = try #require(specs.first)
        #expect(specs.count == 1 && spec.target == .input("radius") && spec.quantity == .radius)
        #expect(spec.value == 1 && spec.count == 12)
        guard case let .radial(center, radius, normal, toward, _) = spec.geometry else {
            Issue.record("expected a radial dimension")
            return
        }
        #expect(isClose(radius, 1))
        // The first edge is the vertical one at the (-10, -5) corner of the 20 x 10 x 10 box (z from 0 to 10). Its faces face -x and
        // -y, so the outward bisector is (-1, -1, 0) / sqrt(2) and the arc's centre sits r / sin(45 deg) = sqrt(2) inside it.
        let diagonal = 1 / 2.0.squareRoot()
        #expect(isClose(center, Vector3(-9, -4, 5)))
        #expect(isClose(toward, Vector3(-diagonal, -diagonal, 0)))
        #expect(isClose(normal, .unitZ))
    }

    @Test func aChamferDimensionsItsDistanceAlongTheFirstFace() async throws {
        var h = Harness()
        let chamfer = allEdgesOfABox(&h, into: ChamferNode.self, ["distance": .number(2)])
        let kernel = OCCTKernel()
        let report = try await h.run([chamfer], kernel: kernel)
        let spec = try #require(report.results[chamfer.id]?.dimensions.first)
        #expect(spec.target == .input("distance") && spec.quantity == .length && spec.value == 2 && spec.count == 12)
        guard case let .linear(from, to, direction, side, _) = spec.geometry else {
            Issue.record("expected a linear dimension")
            return
        }
        #expect(isClose(from, Vector3(-10, -5, 5)) && isClose(to, Vector3(-8, -5, 5)))
        #expect(isClose(direction, .unitX) && isClose(side, Vector3(0, -1, 0)))
    }
    #endif

    // MARK: - Degenerate edges

    /// A solid whose topology is exactly `faces` and `edges` (the guards read nothing else).
    final class Bare: SolidStorage {
        let estimatedBytes = 0
    }

    func set(faces: [FaceInfo], edges: [EdgeInfo]) -> EdgeSet {
        let solid = Solid(topology: Topology(faces: faces, edges: edges),
                          bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: Bare())
        return EdgeSet(solid: solid, edges: edges.map(\.id))
    }

    func face(_ id: Int, normal: Vector3?, centroid: Vector3) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: .plane, normal: normal, area: 1, centroid: centroid, tags: [])
    }

    func edge(faces: [Int], direction: Vector3? = .unitY, midpoint: Vector3 = .zero) -> EdgeInfo {
        EdgeInfo(id: EdgeID(0), kind: .line, direction: direction, length: 1, midpoint: midpoint, convexity: .convex,
                 faces: faces.map(FaceID.init))
    }

    /// A right-angled edge along y at the origin between a floor (normal +z) and a wall (normal +x).
    var rightAngle: [FaceInfo] {
        [face(1, normal: .unitZ, centroid: Vector3(-1, 0, 0)), face(2, normal: .unitX, centroid: Vector3(0, 0, -1))]
    }

    @Test func aRightAngledEdgeHasACorner() throws {
        let corner = try #require(EdgeDimensions.corner(of: set(faces: rightAngle, edges: [edge(faces: [1, 2])])))
        #expect(isClose(corner.interior, Double.pi / 2))
        #expect(isClose(corner.bisector, Vector3(1, 0, 1) * (1 / 2.0.squareRoot())))
    }

    @Test func eachGuardOfTheCornerRefuses() {
        // No edge in the set.
        #expect(EdgeDimensions.corner(of: set(faces: rightAngle, edges: [])) == nil)
        // A seam: one face on both sides.
        #expect(EdgeDimensions.corner(of: set(faces: rightAngle, edges: [edge(faces: [1, 1])])) == nil)
        // Not two faces, or a face the table lacks.
        #expect(EdgeDimensions.corner(of: set(faces: rightAngle, edges: [edge(faces: [1])])) == nil)
        #expect(EdgeDimensions.corner(of: set(faces: rightAngle, edges: [edge(faces: [1, 9])])) == nil)
        // No direction, or a midpoint that is not finite.
        #expect(EdgeDimensions.corner(of: set(faces: rightAngle, edges: [edge(faces: [1, 2], direction: nil)])) == nil)
        #expect(EdgeDimensions.corner(of: set(faces: rightAngle, edges: [edge(faces: [1, 2], midpoint: Vector3(.nan, 0, 0))])) == nil)
        // A face without a normal.
        let unnormalled = [face(1, normal: nil, centroid: Vector3(-1, 0, 0)), rightAngle[1]]
        #expect(EdgeDimensions.corner(of: set(faces: unnormalled, edges: [edge(faces: [1, 2])])) == nil)
        // A flat edge: both faces face the same way, so there is nothing to round.
        let flat = [rightAngle[0], face(2, normal: .unitZ, centroid: Vector3(1, 0, 0))]
        #expect(EdgeDimensions.corner(of: set(faces: flat, edges: [edge(faces: [1, 2])])) == nil)
        // A knife edge: opposite normals, so the bisector vanishes.
        let knife = [rightAngle[0], face(2, normal: -.unitZ, centroid: Vector3(1, 0, 0))]
        #expect(EdgeDimensions.corner(of: set(faces: knife, edges: [edge(faces: [1, 2])])) == nil)
        // A face whose centroid lies on the edge's line has no direction into the face.
        let onTheEdge = [rightAngle[0], face(2, normal: .unitX, centroid: Vector3(0, 5, 0))]
        #expect(EdgeDimensions.corner(of: set(faces: onTheEdge, edges: [edge(faces: [1, 2])])) == nil)
    }

    @Test func aDegenerateEdgeGivesNoFilletOrChamfer() {
        let seam = set(faces: rightAngle, edges: [edge(faces: [1, 1])])
        #expect(EdgeDimensions.fillet(seam, radius: 1).isEmpty)
        #expect(EdgeDimensions.chamfer(seam, distance: 1).isEmpty)
        let good = set(faces: rightAngle, edges: [edge(faces: [1, 2])])
        #expect(EdgeDimensions.fillet(good, radius: 0).isEmpty)
        #expect(EdgeDimensions.chamfer(good, distance: .nan).isEmpty)
        #expect(EdgeDimensions.fillet(good, radius: 1).count == 1)
    }

    @Test func aFilletWithNoEdgesFailsAndDeclaresNothing() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let chamfer = h.add(ChamferNode.self)
        let none = h.add(EdgesByDirectionNode.self, ["direction": .vector(Vector3(1, 1, 1))])
        h.wire(box, "solid", to: none, "solid")
        h.wire(none, "edges", to: chamfer, "edges")
        let report = try await h.run([chamfer])
        #expect(report.error(chamfer) != nil)
        #expect(try #require(report.results[chamfer.id]).dimensions.isEmpty)
    }
}

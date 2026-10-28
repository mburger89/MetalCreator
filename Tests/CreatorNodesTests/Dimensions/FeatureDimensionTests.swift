import Foundation
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
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
        // A 90 degree edge: the centre is the midpoint pulled in along the bisector by r / sin(45 deg).
        #expect(isClose(toward.length, 1) && isClose(normal.length, 1) && abs(normal.dot(toward)) < 1e-9)
        let midpoint = center + toward * (1 / sin(Double.pi / 4))
        let onBoundary = [isClose(abs(midpoint.x), 10), isClose(abs(midpoint.y), 5), isClose(midpoint.z, 0) || isClose(midpoint.z, 10)]
        #expect(onBoundary.count { $0 } >= 2)
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
        #expect(isClose((to - from).length, 2))
        #expect(isClose(direction.length, 1) && isClose(side.length, 1))
        #expect(abs(direction.dot(side)) < 1e-9)
        #expect(isClose(direction, (to - from) * 0.5))
        // `from` is the edge midpoint: on the box boundary in at least two of the three axes.
        let onBoundary = [isClose(abs(from.x), 10), isClose(abs(from.y), 5), isClose(from.z, 0) || isClose(from.z, 10)]
        #expect(onBoundary.count { $0 } >= 2)
    }
    #endif

    @Test func aDegenerateEdgeSetGivesNoDimension() async throws {
        var h = Harness()
        let fillet = h.add(FilletNode.self)
        let report = try await h.run([fillet])
        #expect(report.results[fillet.id]?.dimensions.isEmpty ?? true)
        // A solid with no edges selected: the evaluation fails and declares nothing.
        let box = h.box(10, 10, 10)
        let chamfer = h.add(ChamferNode.self)
        let none = h.add(EdgesByDirectionNode.self, ["direction": .vector(Vector3(1, 1, 1))])
        h.wire(box, "solid", to: none, "solid")
        h.wire(none, "edges", to: chamfer, "edges")
        let second = try await h.run([chamfer])
        #expect(second.results[chamfer.id]?.dimensions.isEmpty ?? true)
    }
}

import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct FakeKernelTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    @Test func extrudedRectangleHasCapsAndFourSides() async throws {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(.rectangle(width: 60, height: 40, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        #expect(solid.topology.faces.count == 6)
        #expect(solid.topology.edges.count == 12)
        #expect(solid.bounds.size == Vector3(60, 40, 6))
        let roles = Set(solid.topology.faces.flatMap(\.tags).map(\.role))
        #expect(roles.contains(.endCap) && roles.contains(.side(segment: 3)))
        #expect(await kernel.operationLog == ["extrude"])
    }

    @Test func symmetricExtrudeStraddlesThePlane() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 2, height: 2, plane: .xy), distance: 6, mode: .symmetric, tag: tag)
        #expect(solid.bounds.min.z == -3)
        #expect(solid.bounds.max.z == 3)
    }

    @Test func extrudedCircleHasASeam() async throws {
        let solid = try await FakeKernel().extrude(.circle(radius: 2, center: .zero, plane: .xy), distance: 5, mode: .oneSided, tag: tag)
        #expect(solid.topology.edges.contains(where: { $0.isSeam }))
    }

    @Test(arguments: [0.0, -1.0, .nan, .infinity])
    func nonPositiveOrNonFiniteDistanceIsRejected(_ distance: Double) async {
        await #expect(throws: KernelError.self) {
            try await FakeKernel().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: distance, mode: .oneSided, tag: tag)
        }
    }

    @Test func filletAddsABlendFacePerEdge() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 60, height: 40, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        let vertical = box.topology.edges.filter { $0.direction == .unitZ }.map(\.id)
        let filleted = try await kernel.fillet(box, edges: vertical, radius: 2, tag: NodeTag(node: NodeID(), item: 0))
        #expect(filleted.topology.faces.count == 6 + vertical.count)
    }

    @Test func oversizedFilletReportsTheLimit() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 60, height: 40, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(box, edges: [EdgeID(0)], radius: 4, tag: tag)
        }
        #expect(error == .filletFailed(radius: 4, maxRadius: 3, reason: "radius too large for the part"))
    }

    @Test func filletWithNoEdgesIsRejected() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 6, height: 6, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        await #expect(throws: KernelError.invalidInput("No edges are selected.")) {
            try await kernel.fillet(box, edges: [], radius: 1, tag: tag)
        }
    }

    @Test func subtractKeepsToolFacesForTagging() async throws {
        let kernel = FakeKernel()
        let plate = try await kernel.extrude(.rectangle(width: 60, height: 40, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        let hole = try await kernel.extrude(.circle(radius: 2.5, center: .zero, plane: .xy), distance: 6, mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let result = try await kernel.boolean(.subtract, plate, [hole], tag: tag)
        #expect(result.bounds == plate.bounds)
        #expect(result.topology.faces.count == plate.topology.faces.count + hole.topology.faces.count)
        #expect(Set(result.topology.faces.map(\.id)).count == result.topology.faces.count)
    }

    @Test func revolveIsUnsupported() async {
        await #expect(throws: KernelError.unsupported("revolve")) {
            try await FakeKernel().revolve(.rectangle(width: 1, height: 1, plane: .xz), axis: .z, angle: .degrees(360), tag: tag)
        }
    }
}

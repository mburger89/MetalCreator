import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct KernelAdditionsTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    @Test func fakeKernelReportsBoxProperties() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 30, mode: .oneSided, tag: tag)
        let properties = try await kernel.properties(of: box)
        #expect(properties.volume == 6000)
        let expectedArea: Double = 2 * (10 * 20 + 20 * 30 + 30 * 10)
        #expect(properties.surfaceArea == expectedArea)
        #expect(properties.centroid == Vector3(0, 0, 15))
    }

    @Test func fakeKernelSkipsPropertiesWhenCancelled() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided, tag: tag)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.properties(of: box)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func unnamedRoleHasAStableSortKey() {
        #expect(TopoRole.unnamed(face: 3).sortKey == "unnamed(3)")
    }

    @Test(arguments: [
        TopoRole.startCap, .endCap, .side(segment: 2), .unnamed(face: 7),
        .blend(sourceEdge: EdgeKey([TopoTag(node: NodeID(), item: 0, role: .endCap)], [TopoTag(node: NodeID(), item: 1, role: .side(segment: 0))])),
    ])
    func rolesRoundTripThroughJSON(_ role: TopoRole) throws {
        let data = try JSONEncoder().encode(role)
        #expect(try JSONDecoder().decode(TopoRole.self, from: data) == role)
    }

    @Test func edgeKeyRoundTripsAndStaysCanonical() throws {
        let a: Set = [TopoTag(node: NodeID(), item: 0, role: .endCap)]
        let b: Set = [TopoTag(node: NodeID(), item: 0, role: .side(segment: 1)), TopoTag(node: NodeID(), item: 2, role: .startCap)]
        let key = EdgeKey(b, a)
        let decoded = try JSONDecoder().decode(EdgeKey.self, from: try JSONEncoder().encode(key))
        #expect(decoded == key)
        #expect(decoded.sortKey == key.sortKey)
    }

    @Test func tagRoundTrips() throws {
        let tag = TopoTag(node: NodeID(), item: 4, role: .side(segment: 3))
        #expect(try JSONDecoder().decode(TopoTag.self, from: try JSONEncoder().encode(tag)) == tag)
    }
}

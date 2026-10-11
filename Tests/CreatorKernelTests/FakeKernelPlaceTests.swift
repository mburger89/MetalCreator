import CreatorGeometry
import Foundation
import Testing
@testable import CreatorKernel

struct FakeKernelPlaceTests {
    let tag = NodeTag(node: NodeID(), item: 0)
    let toolNode = NodeID()

    func qualify(_ node: NodeID) -> NodeID {
        var bytes = node.rawValue.uuid
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        return NodeID(rawValue: UUID(uuid: bytes))
    }

    func tool(_ kernel: FakeKernel) async throws -> Solid {
        try await kernel.extrude(.circle(radius: 2, center: .zero, plane: .xy), distance: 5, mode: .oneSided,
                                 tag: NodeTag(node: toolNode, item: 0))
    }

    @Test func oneKernelCallPlacesEveryCopy() async throws {
        let kernel = FakeKernel()
        let source = try await tool(kernel)
        await kernel.clearLog()
        let moves = (0..<5).map { Transform(translation: Vector3(Double($0) * 10, 0, 0)) }
        let copies = try await kernel.place(Array(repeating: source, count: 5), at: moves, qualifying: { qualify($0) }, tag: tag)
        #expect(copies.count == 5)
        #expect(await kernel.operationLog == ["place"])
    }

    @Test func eachCopyIsNamedByItsIndex() async throws {
        let kernel = FakeKernel()
        let source = try await tool(kernel)
        let copies = try await kernel.place([source, source, source], at: Array(repeating: .identity, count: 3),
                                            qualifying: { qualify($0) }, tag: tag)
        for (index, copy) in copies.enumerated() {
            let tags = Set(copy.topology.faces.flatMap(\.tags))
            #expect(tags.allSatisfy { $0.item == index && $0.node == qualify(toolNode) })
            #expect(tags.contains(TopoTag(node: qualify(toolNode), item: index, role: .endCap)))
        }
        // The tool itself is untouched.
        #expect(source.topology.faces.flatMap(\.tags).allSatisfy { $0.node == toolNode && $0.item == 0 })
    }

    @Test func boundsFollowTheMove() async throws {
        let kernel = FakeKernel()
        let source = try await tool(kernel)
        let turn = Transform(translation: Vector3(0, 0, 10), rotationAxis: Axis(origin: .zero, direction: .unitY), rotation: .degrees(90))
        let copies = try await kernel.place([source], at: [turn], qualifying: { qualify($0) }, tag: tag)
        // The 4 × 4 × 5 cylinder stands on +Z; turned a quarter about Y it lies along +X, then rises 10.
        #expect(isClose(copies[0].bounds.min, Vector3(0, -2, 8)))
        #expect(isClose(copies[0].bounds.max, Vector3(5, 2, 12)))
    }

    @Test func noCopiesIsNotAnError() async throws {
        let copies = try await FakeKernel().place([], at: [], qualifying: { $0 }, tag: tag)
        #expect(copies.isEmpty)
    }

    @Test func eachToolNeedsAPlacement() async throws {
        let kernel = FakeKernel()
        let source = try await tool(kernel)
        await #expect(throws: KernelError.self) {
            try await kernel.place([source, source], at: [.identity], qualifying: { $0 }, tag: tag)
        }
    }

    func isClose(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length < 1e-9 }
}

import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct PlaceConformanceTests {
    let place = NodeID()

    /// What `NodeID.instanceScoped([place, node])` does in the app, without CreatorGraph.
    func qualify(_ node: NodeID) -> NodeID {
        var bytes = node.rawValue.uuid
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        bytes.0 ^= place.rawValue.uuid.0
        return NodeID(rawValue: UUID(uuid: bytes))
    }

    /// A Ø5 pin 10 long standing on the origin, facing +Z.
    func pin(_ kernel: any Kernel, node: NodeID) async throws -> Solid {
        try await kernel.extrude(.circle(radius: 2.5, center: .zero, plane: .xy), distance: 10, mode: .oneSided,
                                 tag: NodeTag(node: node, item: 0))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func copiesKeepTheToolsVolumeAndMoveWithTheirTransform(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tool = try await pin(kernel, node: NodeID())
        let moves = [Transform(translation: Vector3(20, 0, 0)), Transform(translation: Vector3(0, 30, 5)),
                     Plane.yz.placement ?? .identity,
        ]
        let copies = try await kernel.place([tool, tool, tool], at: moves, qualifying: { qualify($0) }, tag: newTag())
        let volume = try await kernel.properties(of: tool).volume
        for copy in copies { #expect(isClose(try await kernel.properties(of: copy).volume, volume)) }
        #expect(isClose(copies[0].bounds.min.x, 17.5) && isClose(copies[0].bounds.max.z, 10))
        #expect(isClose(copies[1].bounds.min.z, 5) && isClose(copies[1].bounds.max.y, 32.5))
        // Facing +X: the pin's length now runs along X.
        #expect(isClose(copies[2].bounds.max.x, 10) && isClose(copies[2].bounds.max.z, 2.5))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func eachCopyCarriesTheToolsTagsQualifiedByItsIndex(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let toolNode = NodeID()
        let tool = try await pin(kernel, node: toolNode)
        let moves = (0..<4).map { Transform(translation: Vector3(Double($0) * 10, 0, 0)) }
        let copies = try await kernel.place(Array(repeating: tool, count: 4), at: moves, qualifying: { qualify($0) }, tag: newTag())
        for (index, copy) in copies.enumerated() {
            #expect(copy.topology.faces.count == tool.topology.faces.count)
            let tags = Set(copy.topology.faces.flatMap(\.tags))
            #expect(tags.allSatisfy { $0.node == qualify(toolNode) && $0.item == index })
            #expect(Set(tags.map(\.role)) == Set(tool.topology.faces.flatMap(\.tags).map(\.role)))
        }
        #expect(tool.topology.faces.flatMap(\.tags).allSatisfy { $0.node == toolNode })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func placedToolsSubtractInOneBooleanAndNameTheirWalls(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let plateTag = newTag()
        let plate = try await box(kernel, 60, 40, 6, tag: plateTag)
        let toolNode = NodeID()
        let hole = try await kernel.extrude(.circle(radius: 2.5, center: .zero, plane: Plane.xy.offset(by: -1)), distance: 8,
                                            mode: .oneSided, tag: NodeTag(node: toolNode, item: 0))
        let moves = [-20.0, 0, 20].map { Transform(translation: Vector3($0, 5, 0)) }
        let tools = try await kernel.place([hole, hole, hole], at: moves, qualifying: { qualify($0) }, tag: newTag())
        let result = try await kernel.boolean(.subtract, plate, tools, tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 14400 - 3 * Double.pi * 6.25 * 6))
        for index in 0..<3 {
            let name = TopoTag(node: qualify(toolNode), item: index, role: .side(segment: 0))
            #expect(result.topology.faces.filter { $0.tags.contains(name) }.count == 1)
        }
        #expect(faces(result, role: .endCap, of: plateTag).count == 1)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aMismatchedPlacementListIsRefused(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tool = try await pin(kernel, node: NodeID())
        await #expect(throws: KernelError.self) {
            try await kernel.place([tool, tool], at: [.identity], qualifying: { qualify($0) }, tag: newTag())
        }
        await #expect(throws: KernelError.self) {
            try await kernel.place([tool], at: [Transform(translation: Vector3(.nan, 0, 0))], qualifying: { qualify($0) },
                                   tag: newTag())
        }
        let none = try await kernel.place([], at: [], qualifying: { qualify($0) }, tag: newTag())
        #expect(none.isEmpty)
    }
}

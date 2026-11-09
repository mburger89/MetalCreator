import CreatorGraph
import CreatorKernel
import CreatorMCP
import CreatorNodes
import Testing

@MainActor struct AddressingTests {
    @Test func addressesByIDAndUniqueName() async throws {
        let fixture = try await SessionFixture()
        let graph = fixture.document.graph
        let byName = Addressing.node(.string("Extrude"), in: graph)
        #expect(try byName.get() == fixture.extrude)
        let byID = Addressing.node(.string(fixture.extrude.rawValue.uuidString), in: graph)
        #expect(try byID.get() == fixture.extrude)
        let endpoint = Addressing.endpoint("Extrude.solid", in: graph, registry: fixture.document.registry, output: true)
        #expect(try endpoint.get() == Endpoint(node: fixture.extrude, socket: "solid"))
        let missing = Addressing.node(.string("Nope"), in: graph)
        #expect(missing == .failure(Refusal("There's no node called “Nope”.")))
        let unknownID = "00000000-0000-0000-0000-000000000001"
        #expect(Addressing.node(.string(unknownID), in: graph) == .failure(Refusal("There's no node with ID \(unknownID).")))
    }

    @Test func unknownSocketIsNamed() async throws {
        let fixture = try await SessionFixture()
        let graph = fixture.document.graph
        let registry = fixture.document.registry
        #expect(Addressing.endpoint("Extrude.nope", in: graph, registry: registry, output: false)
            == .failure(Refusal("Extrude has no input called “nope”.")))
        #expect(Addressing.endpoint("Extrude.distance", in: graph, registry: registry, output: true)
            == .failure(Refusal("Extrude has no output called “distance”.")))
    }

    @Test func ambiguousNameIsRefused() async throws {
        let fixture = try await SessionFixture()
        for _ in 0..<2 {
            var box = fixture.document.registry.makeNode("creator.number")
            box.name = "Box"
            try fixture.document.perform(.addNode(box), name: "Add Node")
        }
        let result = try await fixture.call("get_node", .object(["node": .string("Box")]))
        #expect(result.isError)
        #expect(result.0 == .string("Two nodes are called “Box”; use the node's ID."))
    }
}

import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// Which selections preview, and the field they show (fields spec §6).
@MainActor
struct FieldPreviewSelectionTests {
    let registry = BuiltInNodes.registry

    func evaluate(_ builder: GraphBuilder, demanding nodes: [Node]) async throws -> [NodeID: NodeResult] {
        try await Evaluator(registry: registry, kernel: FakeKernel()).evaluate(builder.graph, demand: Set(nodes.map(\.id))).results
    }

    func field(_ node: Node, _ builder: GraphBuilder, _ results: [NodeID: NodeResult]) -> Field? {
        FieldPreviewSelection.field(of: node, graph: builder.graph, results: results, registry: registry)
    }

    @Test func aSourceAndAMathsNodeShowTheFieldTheyMake() async throws {
        var builder = GraphBuilder()
        let radial = builder.add(RadialGradientNode.self, ["radius": .number(20)])
        let remap = builder.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(1), "toLow": .number(1), "toHigh": .number(0),
        ])
        builder.wire(radial, "field", to: remap, "field")
        let results = try await evaluate(builder, demanding: [remap])
        #expect(field(radial, builder, results)?.description == "radial(radius 20)")
        #expect(field(remap, builder, results)?.description == "remap(radial(radius 20), 0…1 → 1…0)")
    }

    @Test func theNodesThatTakeAFieldShowTheWiredOne() async throws {
        var builder = GraphBuilder()
        let radial = builder.add(RadialGradientNode.self, ["radius": .number(20)])
        let sample = builder.add(SampleFieldNode.self)
        let cull = builder.add(CullByFieldNode.self)
        let scatter = builder.add(FieldScatterNode.self)
        for node in [sample, cull, scatter] { builder.wire(radial, "field", to: node, "field") }
        let results = try await evaluate(builder, demanding: [radial])
        for node in [sample, cull, scatter] {
            #expect(field(node, builder, results)?.description == "radial(radius 20)", "\(node.name)")
        }
    }

    @Test func anUnwiredFieldInputHasNothingToShow() async throws {
        var builder = GraphBuilder()
        let sample = builder.add(SampleFieldNode.self)
        let scatter = builder.add(FieldScatterNode.self)
        let results = try await evaluate(builder, demanding: [sample])
        #expect(field(sample, builder, results) == nil && field(scatter, builder, results) == nil, "a typed number is a constant")
    }

    @Test func aNodeThatFailedMakesNoFieldAndOneWhoseUpstreamFailedTakesNone() async throws {
        var builder = GraphBuilder()
        let radial = builder.add(RadialGradientNode.self, ["radius": .number(0)])
        let sample = builder.add(SampleFieldNode.self)
        builder.wire(radial, "field", to: sample, "field")
        let results = try await evaluate(builder, demanding: [radial])
        #expect(!(results[radial.id]?.state.isSuccess ?? true))
        #expect(field(radial, builder, results) == nil && field(sample, builder, results) == nil)
    }

    @Test func onlyFieldsNodesPreview() {
        var builder = GraphBuilder()
        let number = builder.add(NumberNode.self)
        let noise = builder.add(NoiseFieldNode.self)
        let scatter = builder.add(FieldScatterNode.self)
        let cull = builder.add(CullByRegionNode.self)
        #expect(!FieldPreviewSelection.previews(number, registry: registry) && !FieldPreviewSelection.previews(cull, registry: registry))
        #expect(FieldPreviewSelection.previews(noise, registry: registry) && FieldPreviewSelection.previews(scatter, registry: registry))
    }

    @Test func aNodeTheRegistryDoesNotKnowIsNotPreviewed() {
        let stranger = Node(typeID: "creator.nothing", name: "Nothing")
        #expect(!FieldPreviewSelection.previews(stranger, registry: registry))
        #expect(FieldPreviewSelection.field(of: stranger, graph: Graph(), results: [:], registry: registry) == nil)
    }
}

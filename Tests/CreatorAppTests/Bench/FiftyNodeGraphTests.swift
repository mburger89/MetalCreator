import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorApp

/// The 50-node benchmark graph is what spec §7.3 asks for: fifty real nodes, wired as a person would, every one of
/// them evaluating. Runs in the default test run.
@MainActor
struct FiftyNodeGraphTests {
    @Test func itHasFiftyNodesAndFortyValidWires() {
        let graph = FiftyNodeGraph.make()
        #expect(graph.nodes.count == 50)
        #expect(graph.links.count == 40)
        for link in graph.links {
            var without = graph
            without.links.removeAll { $0 == link }
            #expect(without.connectionProblem(from: link.from, to: link.to, registry: BuiltInNodes.registry) == nil)
        }
    }

    @Test func noTwoNodesShareAPlace() {
        let positions = FiftyNodeGraph.make().nodes.values.map(\.position)
        #expect(Set(positions.map { "\($0.x),\($0.y)" }).count == 50)
    }

    @Test func everyNodeEvaluates() async {
        let app = await makeApp(FiftyNodeGraph.make())
        expectAllOK(app, "the 50-node graph")
    }
}

import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The blended join between a lattice's skin and its lattice (implicit spec Errata D18): the `blend` input on the three lattice nodes,
/// its default of 1 mm on a new node, and the 0 (the sharp join) that a graph saved before 7c-3f reads.
struct LatticeSkinBlendTests {
    /// The three lattice nodes, each with settings that give a lattice inside a 40 mm cube with a 1.5 mm skin.
    static let nodes: [(definition: any NodeDefinition.Type, settings: [SocketName: ConstantValue])] = [
        (TPMSNode.self, ["skin": .number(1.5), "cell size": .number(8), "thickness": .number(1)]),
        (StrutLatticeNode.self, ["skin": .number(1.5), "cell size": .number(8), "strut radius": .number(0.6)]),
        (VoronoiLatticeNode.self, ["skin": .number(1.5), "count": .integer(30), "thickness": .number(0.8)]),
    ]

    /// A 40 mm cube wired into a lattice node of `definition`.
    func lattice(_ h: inout Harness, _ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue]) -> Node {
        let cube = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let node = h.add(definition, values)
        h.wire(cube, "implicit", to: node, "region")
        return node
    }

    func solid(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue]) async throws -> ImplicitSolid {
        var h = Harness()
        let node = lattice(&h, definition, values)
        return try #require(try await h.run([node]).implicitSolid(node))
    }

    /// Points through the layer round the skin's inner face (x = 18.5) where the lattice meets it: 0.25 mm apart across the layer, 1.1 mm
    /// apart along it.
    static let samples: [Vector3] = (-6...6).flatMap { layer in
        (-15...15).flatMap { j in (-15...15).map { k in Vector3(18.5 + Double(layer) * 0.25, Double(j) * 1.1, Double(k) * 1.1) } }
    }

    /// Whether two solids agree at every sample, and where the first differs: the points and values.
    static func agree(_ a: ImplicitSolid, _ b: ImplicitSolid) -> Bool {
        samples.allSatisfy { abs(a.signedDistance(at: $0) - b.signedDistance(at: $0)) < 1e-12 }
    }

    @Test(arguments: Self.nodes.indices) func aNewNodeHasABlendOfOneMillimetre(_ index: Int) throws {
        let definition = Self.nodes[index].definition
        let spec = try #require(definition.inputs.first { $0.name == "blend" })
        #expect(spec.type == .number && spec.defaultValue == .number(1) && spec.unit == .millimetres)
        #expect(definition.typeVersion == 2)
        #expect(definition.inspector.flatMap(\.controls).contains(.number("blend")), "the inspector shows it like the skin")
    }

    @Test(arguments: Self.nodes.indices) func theSkinJoinsTheLatticeWithASmoothUnionOfTheBlendRadius(_ index: Int) async throws {
        let (definition, settings) = Self.nodes[index]
        let blended = try await solid(definition, settings)
        #expect(blended.description.contains("blend 1 mm"), "the default 1 mm: \(blended.description)")
        let sharp = try await solid(definition, settings.merging(["blend": .number(0)]) { _, given in given })
        #expect(sharp.description.hasPrefix("union(shell("), "blend 0 is the sharp union: \(sharp.description)")
        #expect(!sharp.description.contains("blend 1 mm"))
        // A smooth union is never farther than the sharp one, and is nearer where the two parts meet.
        let pairs = Self.samples.map { (blended.signedDistance(at: $0), sharp.signedDistance(at: $0)) }
        #expect(pairs.allSatisfy { $0.0 <= $0.1 + 1e-9 }, "never farther than the sharp union")
        #expect(pairs.contains { $0.0 < $0.1 - 0.05 }, "the join fills the crease between the skin and the lattice")
    }

    @Test(arguments: Self.nodes.indices) func withoutASkinTheBlendChangesNothing(_ index: Int) async throws {
        let (definition, settings) = Self.nodes[index]
        let plain = settings.merging(["skin": .number(0)]) { _, given in given }
        let one = try await solid(definition, plain)
        let five = try await solid(definition, plain.merging(["blend": .number(5)]) { _, given in given })
        #expect(one.description == five.description && Self.agree(one, five))
    }

    /// One case per blend, not a loop: the Windows 6.4 toolchain asserts on an async function that holds a loop's locals across an await.
    @Test(arguments: Self.nodes.indices, [-1.0, Double.nan, Double.infinity])
    func aNegativeOrNonFiniteBlendIsRefused(_ index: Int, _ bad: Double) async throws {
        let (definition, settings) = Self.nodes[index]
        var h = Harness()
        let node = lattice(&h, definition, settings.merging(["blend": .number(bad)]) { _, given in given })
        #expect(try await h.run([node]).error(node) == "“blend” must be 0 or more.", "\(bad)")
    }

    // MARK: Files

    @Test(arguments: Self.nodes.indices) func theBlendSurvivesASaveAndReopen(_ index: Int) async throws {
        let (definition, settings) = Self.nodes[index]
        var h = Harness()
        let node = lattice(&h, definition, settings.merging(["blend": .number(2.5)]) { _, given in given })
        let data = try GraphFileIO.encode(GraphFile(graph: h.graph))
        let file = try GraphFileIO.decode(data, registry: BuiltInNodes.registry)
        let loaded = try #require(file.graph.nodes[node.id])
        #expect(loaded.typeVersion == 2 && loaded.inputValues["blend"] == .number(2.5))
        #expect(file.graph.nodes == h.graph.nodes)
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel()).evaluate(file.graph, demand: [node.id])
        #expect(try #require(report.implicitSolid(node)).description.contains("blend 2.5 mm"))
    }

    /// A graph saved before 7c-3f has no `blend` and node version 1: it reads 0, so its geometry does not change.
    @Test(arguments: Self.nodes.indices) func aFileWithoutABlendKeyReadsZeroAndKeepsItsGeometry(_ index: Int) async throws {
        let (definition, settings) = Self.nodes[index]
        var h = Harness()
        var old = lattice(&h, definition, settings)
        old.typeVersion = 1
        old.inputValues["blend"] = nil
        var graph = h.graph
        graph.nodes[old.id] = old
        let data = try GraphFileIO.encode(GraphFile(graph: graph))
        let file = try GraphFileIO.decode(data, registry: BuiltInNodes.registry)
        let loaded = try #require(file.graph.nodes[old.id])
        #expect(loaded.typeVersion == 2)
        #expect(loaded.inputValues["blend"] == .number(0), "an old node keeps the sharp join")
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel()).evaluate(file.graph, demand: [old.id])
        let reopened = try #require(report.implicitSolid(old))
        let sharp = try await solid(definition, settings.merging(["blend": .number(0)]) { _, given in given })
        #expect(reopened.description == sharp.description && Self.agree(reopened, sharp), "\(reopened.description)")
        #expect(!reopened.description.contains("blend 1 mm"))
        // A node already at version 2 whose file lacks the key (hand-edited) is not rewritten, and reads the socket's 1 mm.
        var current = old
        current.typeVersion = 2
        graph.nodes[old.id] = current
        let again = try GraphFileIO.decode(try GraphFileIO.encode(GraphFile(graph: graph)), registry: BuiltInNodes.registry)
        #expect(again.graph.nodes[old.id]?.inputValues["blend"] == nil)
    }
}

import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The `continuity` input on Union, Subtract, Intersect and the three lattices (G-a of the G2 surfacing spec): G2 on a new Union, Subtract or Intersect, G1 on a new
/// lattice (its skin join is tuned for printability) and on a node saved before it, and one socket for a Strut Lattice's skin and joints.
struct BlendContinuityMigrationTests {
    static let combiners: [any NodeDefinition.Type] = [ImplicitUnionNode.self, ImplicitSubtractNode.self, ImplicitIntersectNode.self]
    static let lattices: [any NodeDefinition.Type] = [TPMSNode.self, StrutLatticeNode.self, VoronoiLatticeNode.self]

    @Test(arguments: combiners.indices) func aNewCombinerIsG2(_ index: Int) throws {
        let definition = Self.combiners[index]
        let spec = try #require(definition.inputs.first { $0.name == "continuity" })
        #expect(spec.type == .integer && spec.defaultValue == .integer(1))
        #expect(definition.typeVersion == 2)
        #expect(definition.inspector.flatMap(\.controls).contains(.segmented("continuity", options: ["G1", "G2", "G3"])))
    }

    @Test(arguments: lattices.indices) func aNewLatticeIsG1(_ index: Int) throws {
        let definition = Self.lattices[index]
        let spec = try #require(definition.inputs.first { $0.name == "continuity" })
        #expect(spec.defaultValue == .integer(0) && definition.typeVersion == 3)
        #expect(definition.inspector.flatMap(\.controls).contains(.segmented("continuity", options: ["G1", "G2", "G3"])))
    }

    @Test func aNewUnionIsG2() async throws {
        var h = Harness()
        let union = h.add(ImplicitUnionNode.self, ["blend radius": .number(2)])
        h.wire(Self.spheres(&h), "implicit", to: union, "shapes")
        let solid = try #require(try await h.run([union]).implicitSolid(union))
        #expect(solid.description == "union(sphere(radius 10 mm), sphere(radius 5 mm), blend 2 mm, G2)")
    }

    static func spheres(_ h: inout Harness) -> Node {
        let radii = h.add(SeriesNode.self, ["start": .number(10), "step": .number(-5), "count": .integer(2)])
        let spheres = h.add(ImplicitSphereNode.self)
        h.wire(radii, "values", to: spheres, "radius")
        return spheres
    }

    @Test(arguments: 0...2) func continuityReachesTheSolid(_ index: Int) async throws {
        var h = Harness()
        let union = h.add(ImplicitUnionNode.self, ["blend radius": .number(2), "continuity": .integer(index)])
        h.wire(Self.spheres(&h), "implicit", to: union, "shapes")
        let solid = try #require(try await h.run([union]).implicitSolid(union))
        guard case .union(_, _, let continuity) = solid else { Issue.record("not a union: \(solid.description)"); return }
        #expect(continuity.rawValue == index)
    }

    @Test(arguments: combiners.indices) func aSavedCombinerOpensAsG1(_ index: Int) async throws {
        let definition = Self.combiners[index]
        var h = Harness()
        var old = h.add(definition, ["blend radius": .number(2)])
        h.wire(Self.spheres(&h), "implicit", to: old, "shapes")
        old.typeVersion = 1
        old.inputValues["continuity"] = nil
        var graph = h.graph
        graph.nodes[old.id] = old
        let file = try GraphFileIO.decode(try GraphFileIO.encode(GraphFile(graph: graph)), registry: BuiltInNodes.registry)
        let loaded = try #require(file.graph.nodes[old.id])
        #expect(loaded.typeVersion == 2 && loaded.inputValues["continuity"] == .integer(0))
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel()).evaluate(file.graph, demand: [old.id])
        let reopened = try #require(report.implicitSolid(old))
        #expect(!reopened.description.contains("G2"))
        // The same graph made today with G1 chosen is the same solid, point for point.
        var fresh = Harness()
        let node = fresh.add(definition, ["blend radius": .number(2), "continuity": .integer(0)])
        fresh.wire(Self.spheres(&fresh), "implicit", to: node, "shapes")
        let today = try #require(try await fresh.run([node]).implicitSolid(node))
        #expect(today.description == reopened.description)
        for i in -12...12 {
            let p = Vector3(Double(i) * 0.9, Double(i % 5), 0.3)
            #expect(abs(today.signedDistance(at: p) - reopened.signedDistance(at: p)) < 1e-9)
        }
    }

    /// Each lattice node's settings that give a skin with a blend.
    static let latticeSettings: [[SocketName: ConstantValue]] = [
        ["skin": .number(1.5), "cell size": .number(8), "thickness": .number(1)],
        ["skin": .number(1.5), "cell size": .number(8), "strut radius": .number(0.6), "node blend": .number(0.5)],
        ["skin": .number(1.5), "count": .integer(30), "thickness": .number(0.8)],
    ]

    func lattice(_ h: inout Harness, _ index: Int, _ extra: [SocketName: ConstantValue] = [:]) -> Node {
        let cube = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let node = h.add(Self.lattices[index], Self.latticeSettings[index].merging(extra) { _, given in given })
        h.wire(cube, "implicit", to: node, "region")
        return node
    }

    @Test(arguments: lattices.indices) func aVersionOneLatticeRunsBothMigrations(_ index: Int) async throws {
        var h = Harness()
        var old = lattice(&h, index)
        old.typeVersion = 1
        old.inputValues["blend"] = nil
        old.inputValues["continuity"] = nil
        var graph = h.graph
        graph.nodes[old.id] = old
        let file = try GraphFileIO.decode(try GraphFileIO.encode(GraphFile(graph: graph)), registry: BuiltInNodes.registry)
        let loaded = try #require(file.graph.nodes[old.id])
        #expect(loaded.typeVersion == 3)
        #expect(loaded.inputValues["blend"] == .number(0) && loaded.inputValues["continuity"] == .integer(0))
    }

    @Test(arguments: lattices.indices) func aVersionTwoLatticeKeepsItsBlendAndGainsG1(_ index: Int) async throws {
        var h = Harness()
        var old = lattice(&h, index, ["blend": .number(2)])
        old.typeVersion = 2
        old.inputValues["continuity"] = nil
        var graph = h.graph
        graph.nodes[old.id] = old
        let file = try GraphFileIO.decode(try GraphFileIO.encode(GraphFile(graph: graph)), registry: BuiltInNodes.registry)
        let loaded = try #require(file.graph.nodes[old.id])
        #expect(loaded.typeVersion == 3)
        #expect(loaded.inputValues["blend"] == .number(2) && loaded.inputValues["continuity"] == .integer(0))
    }

    @Test(arguments: 0...2) func oneContinuityGovernsTheSkinAndTheJoints(_ order: Int) async throws {
        var h = Harness()
        let node = lattice(&h, 1, ["continuity": .integer(order)])
        let solid = try #require(try await h.run([node]).implicitSolid(node))
        let label = BlendContinuity(rawValue: order)?.label ?? ""
        let skinOrder = order == 0 ? "blend 1 mm)" : "blend 1 mm, \(label))"
        #expect(solid.description.contains(skinOrder), "\(solid.description)")
        #expect(solid.description.contains(order == 0 ? "blend 0.5 mm" : "blend 0.5 mm, \(label)"), "\(solid.description)")
    }

    @Test func aBlendOfZeroCompilesAsG1AndAGradedOneKeepsG2() async throws {
        var h = Harness()
        let plain = h.add(ImplicitUnionNode.self)
        h.wire(Self.spheres(&h), "implicit", to: plain, "shapes")
        let plainSolid = try #require(try await h.run([plain]).implicitSolid(plain))
        #expect(!(try ImplicitCompiler.compile(plainSolid)).source.contains("smoothMin2"), "a default union has blend 0")

        var g = Harness()
        let gradient = g.add(LinearGradientNode.self, ["length": .number(10)])
        let graded = g.add(ImplicitUnionNode.self)
        g.wire(Self.spheres(&g), "implicit", to: graded, "shapes")
        g.wire(gradient, "field", to: graded, "blend radius")
        let gradedSolid = try #require(try await g.run([graded]).implicitSolid(graded))
        #expect(try ImplicitCompiler.compile(gradedSolid).source.contains("smoothMin2"))
    }
}

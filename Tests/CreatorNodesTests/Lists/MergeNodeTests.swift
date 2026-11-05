import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Merge (lists spec follow-up, 2026-11-04): four optional inputs joined into one flat list.
struct MergeNodeTests {
    /// A sphere of radius 10 and a long thin box 60 × 6 × 6, both at the origin.
    func shapes(_ h: inout Harness) -> (sphere: Node, box: Node) {
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(10)])
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(60, 6, 6))])
        return (sphere, box)
    }

    func series(_ h: inout Harness, start: Double = 0, count: Int) -> Node {
        h.add(SeriesNode.self, ["start": .number(start), "count": .integer(count)])
    }

    // MARK: Shapes into the implicit combiners

    @Test func aSphereAndABoxMergeIntoAUnion() async throws {
        var h = Harness()
        let (sphere, box) = shapes(&h)
        let merge = h.add(MergeNode.self)
        h.wire(sphere, "implicit", to: merge, "a")
        h.wire(box, "implicit", to: merge, "b")
        let union = h.add(ImplicitUnionNode.self)
        h.wire(merge, "list", to: union, "shapes")
        let report = try await h.run([union])
        let solid = try #require(report.implicitSolid(union))
        #expect(solid.distance(0, 8, 0) < 0, "inside the sphere only")
        #expect(solid.distance(25, 0, 0) < 0, "inside the box only")
        #expect(solid.distance(15, 8, 0) > 0, "in neither")
        #expect(report.isOK(union))
    }

    @Test func aBlendRadiusJoinsTheMergedShapes() async throws {
        var h = Harness()
        let (sphere, box) = shapes(&h)
        let merge = h.add(MergeNode.self)
        h.wire(sphere, "implicit", to: merge, "a")
        h.wire(box, "implicit", to: merge, "b")
        let union = h.add(ImplicitUnionNode.self, ["blend radius": .number(3)])
        h.wire(merge, "list", to: union, "shapes")
        let solid = try #require(try await h.run([union]).implicitSolid(union))
        #expect(solid.distance(0, 8, 0) < 0 && solid.distance(25, 0, 0) < 0)
        #expect(solid.description.contains("blend 3 mm"))
    }

    @Test func subtractThroughAMergeIsAMinusB() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(10)])
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(60, 6, 6))])
        let merge = h.add(MergeNode.self)
        h.wire(sphere, "implicit", to: merge, "a")
        h.wire(box, "implicit", to: merge, "b")
        let subtract = h.add(ImplicitSubtractNode.self)
        h.wire(merge, "list", to: subtract, "shapes")
        var g = Harness()
        let s2 = g.add(ImplicitSphereNode.self, ["radius": .number(10)])
        let b2 = g.add(ImplicitBoxNode.self, ["size": .vector(Vector3(60, 6, 6))])
        let merge2 = g.add(MergeNode.self)
        g.wire(b2, "implicit", to: merge2, "a")
        g.wire(s2, "implicit", to: merge2, "b")
        let subtract2 = g.add(ImplicitSubtractNode.self)
        g.wire(merge2, "list", to: subtract2, "shapes")

        let aMinusB = try #require(try await h.run([subtract]).implicitSolid(subtract))
        let bMinusA = try #require(try await g.run([subtract2]).implicitSolid(subtract2))
        #expect(aMinusB.distance(0, 8, 0) < 0, "in the sphere, not in the box")
        #expect(aMinusB.distance(0, 0, 0) > 0, "in the box: cut away")
        #expect(bMinusA.distance(0, 8, 0) > 0, "swapped: the sphere is cut from the box")
        #expect(bMinusA.distance(25, 0, 0) < 0, "swapped: the box outside the sphere stays")
        #expect(aMinusB.distance(25, 0, 0) > 0)
    }

    @Test func mergeIntoAnOutputGivesBothPartsAsAList() async throws {
        var h = Harness()
        let one = h.box(10, 10, 10), two = h.box(5, 5, 5, at: Vector3(40, 0, 0))
        let merge = h.add(MergeNode.self)
        h.wire(one, "solid", to: merge, "a")
        h.wire(two, "solid", to: merge, "b")
        let output = h.add(OutputNode.self, output: true)
        h.wire(merge, "list", to: output, "solid")
        let report = try await h.run([output])
        #expect(report.isOK(output))
        #expect(report.value(output, "solid")?.solids?.count == 2)
    }

    // MARK: Order and shapes of input

    @Test func itemsComeInSocketOrderAndGapsAreSkipped() async throws {
        var h = Harness()
        let a = series(&h, start: 1, count: 2), c = series(&h, start: 7, count: 2)
        let merge = h.add(MergeNode.self)
        h.wire(c, "values", to: merge, "c")
        h.wire(a, "values", to: merge, "a")
        let report = try await h.run([merge])
        #expect(report.value(merge, "list")?.outline == "[1,2,7,8]")
    }

    @Test func aListAndASingleValueJoin() async throws {
        var h = Harness()
        let list = series(&h, count: 3)
        let number = h.add(NumberNode.self, ["value": .number(9)])
        let merge = h.add(MergeNode.self)
        h.wire(list, "values", to: merge, "a")
        h.wire(number, "value", to: merge, "b")
        let report = try await h.run([merge])
        #expect(report.value(merge, "list")?.outline == "[0,1,2,9]")
    }

    @Test func aTreeIsFlattenedRowByRow() async throws {
        var h = Harness()
        let partition = h.add(PartitionNode.self, ["size": .integer(2)])
        h.wire(series(&h, count: 5), "values", to: partition, "tree")
        let tail = h.add(NumberNode.self, ["value": .number(50)])
        let merge = h.add(MergeNode.self)
        h.wire(partition, "tree", to: merge, "a")
        h.wire(tail, "value", to: merge, "b")
        let report = try await h.run([merge])
        #expect(report.value(partition, "tree")?.outline == "[[0,1],[2,3],[4]]")
        #expect(report.value(merge, "list")?.outline == "[0,1,2,3,4,50]")
    }

    @Test func aCulledListContributesItsSurvivorsAndTheResultIsNotCulled() async throws {
        var h = Harness()
        let cull = h.add(CullPatternNode.self)
        h.wire(series(&h, count: 4), "values", to: cull, "tree")
        let merge = h.add(MergeNode.self)
        h.wire(cull, "tree", to: merge, "a")
        let report = try await h.run([merge])
        #expect(report.value(cull, "tree")?.outline == "[0,2]")
        let merged = try #require(report.value(merge, "list"))
        #expect(merged.outline == "[0,2]")
        guard case .list = merged else { Issue.record("expected a plain list, got a culled tree"); return }
    }

    @Test func nothingWiredIsAnEmptyList() async throws {
        var h = Harness()
        let merge = h.add(MergeNode.self)
        let report = try await h.run([merge])
        #expect(report.isOK(merge))
        #expect(report.value(merge, "list")?.outline == "[]")
    }

    @Test func emptyInputsAreAnEmptyList() async throws {
        var h = Harness()
        let merge = h.add(MergeNode.self)
        h.wire(series(&h, count: 0), "values", to: merge, "a")
        let report = try await h.run([merge])
        #expect(report.isOK(merge))
        #expect(report.value(merge, "list")?.outline == "[]")
    }

    @Test func aMergeIntoAMergeKeepsOrder() async throws {
        var h = Harness()
        let inner = h.add(MergeNode.self)
        h.wire(series(&h, start: 1, count: 2), "values", to: inner, "a")
        h.wire(series(&h, start: 5, count: 1), "values", to: inner, "b")
        let outer = h.add(MergeNode.self)
        h.wire(series(&h, start: 0, count: 1), "values", to: outer, "a")
        h.wire(inner, "list", to: outer, "b")
        h.wire(series(&h, start: 9, count: 1), "values", to: outer, "c")
        let report = try await h.run([outer])
        #expect(report.value(outer, "list")?.outline == "[0,1,2,5,9]")
    }

    // MARK: Connections

    @Test func solidsImplicitsAndNumbersWireIntoMergeAndMergeWiresIntoShapes() {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let sphere = h.add(ImplicitSphereNode.self)
        let number = h.add(NumberNode.self)
        let merge = h.add(MergeNode.self)
        let union = h.add(ImplicitUnionNode.self)
        h.wire(box, "solid", to: merge, "a")
        h.wire(sphere, "implicit", to: merge, "b")
        h.wire(number, "value", to: merge, "c")
        h.wire(merge, "list", to: union, "shapes")
        #expect(MergeNode.inputs.map(\.name) == ["a", "b", "c", "d"] as [SocketName])
        #expect(MergeNode.inputs.allSatisfy { $0.isOptional && $0.type == .any && $0.access == .tree })
        #expect(MergeNode.outputs.map(\.name) == ["list"] as [SocketName])
    }

    // MARK: Mixed types

    @Test func aSolidAndAnImplicitInUnionSaySo() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let sphere = h.add(ImplicitSphereNode.self)
        let merge = h.add(MergeNode.self)
        h.wire(box, "solid", to: merge, "a")
        h.wire(sphere, "implicit", to: merge, "b")
        let union = h.add(ImplicitUnionNode.self)
        h.wire(merge, "list", to: union, "shapes")
        let report = try await h.run([union])
        #expect(report.error(union) == "“shapes” needs an implicit solid. To Implicit makes one from a solid.")
    }

    @Test func aNumberAndAnImplicitInUnionSaySo() async throws {
        var h = Harness()
        let number = h.add(NumberNode.self)
        let sphere = h.add(ImplicitSphereNode.self)
        let merge = h.add(MergeNode.self)
        h.wire(sphere, "implicit", to: merge, "a")
        h.wire(number, "value", to: merge, "b")
        let union = h.add(ImplicitUnionNode.self)
        h.wire(merge, "list", to: union, "shapes")
        let report = try await h.run([union])
        #expect(report.error(union) == "“shapes” needs an implicit solid. To Implicit makes one from a solid.")
    }
}

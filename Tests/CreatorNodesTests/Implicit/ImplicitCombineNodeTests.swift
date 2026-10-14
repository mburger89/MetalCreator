import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Union, Subtract and Intersect (implicit spec §3.3).
struct ImplicitCombineNodeTests {
    /// Spheres of radius 10 and 5 as one list.
    func spheres(_ h: inout Harness) -> Node {
        let radii = h.add(SeriesNode.self, ["start": .number(10), "step": .number(-5), "count": .integer(2)])
        let spheres = h.add(ImplicitSphereNode.self)
        h.wire(radii, "values", to: spheres, "radius")
        return spheres
    }

    @Test func aUnionOfTwoShapesIsTheirUnion() async throws {
        var h = Harness()
        let union = h.add(ImplicitUnionNode.self)
        h.wire(spheres(&h), "implicit", to: union, "shapes")
        let report = try await h.run([union])
        let solid = try #require(report.implicitSolid(union))
        #expect(solid.description == "union(sphere(radius 10 mm), sphere(radius 5 mm))")
        #expect(solid.distance(0, 0, 0) == -10 && solid.distance(12, 0, 0) == 2)
        #expect(report.isOK(union))
    }

    @Test func subtractCutsTheLaterShapesFromTheFirst() async throws {
        var h = Harness()
        let subtract = h.add(ImplicitSubtractNode.self)
        h.wire(spheres(&h), "implicit", to: subtract, "shapes")
        let solid = try #require(try await h.run([subtract]).implicitSolid(subtract))
        #expect(solid.description == "subtract(sphere(radius 10 mm), sphere(radius 5 mm))")
        #expect(solid.distance(0, 0, 0) == 5, "the small ball is cut from the middle")
        #expect(solid.distance(8, 0, 0) == -2)
    }

    @Test func intersectKeepsWhatIsInEveryShape() async throws {
        var h = Harness()
        let intersect = h.add(ImplicitIntersectNode.self)
        h.wire(spheres(&h), "implicit", to: intersect, "shapes")
        let solid = try #require(try await h.run([intersect]).implicitSolid(intersect))
        #expect(solid.distance(0, 0, 0) == -5 && solid.distance(8, 0, 0) == 3)
    }

    @Test func aBlendRadiusRoundsTheJoin() async throws {
        var h = Harness()
        let union = h.add(ImplicitUnionNode.self, ["blend radius": .number(2)])
        h.wire(spheres(&h), "implicit", to: union, "shapes")
        let solid = try #require(try await h.run([union]).implicitSolid(union))
        #expect(solid.description == "union(sphere(radius 10 mm), sphere(radius 5 mm), blend 2 mm)")
        // Both spheres read −5 at 5 mm from the centre along... the smaller one's surface: it is inside the bigger by 5, so no dip.
        #expect(solid.distance(0, 0, 0) == -10)
        #expect(solid.bounds.max.x == 10.5, "a smooth union may bulge a quarter of the blend radius")
    }

    @Test func oneSharpShapeIsPassedThrough() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(4)])
        let union = h.add(ImplicitUnionNode.self)
        h.wire(sphere, "implicit", to: union, "shapes")
        let solid = try #require(try await h.run([union]).implicitSolid(union))
        #expect(solid.description == "sphere(radius 4 mm)")
    }

    @Test func noShapesWaitForOne() async throws {
        var h = Harness()
        let union = h.add(ImplicitUnionNode.self)
        let report = try await h.run([union])
        guard case .idle(let reason?)? = report.state(union) else { Issue.record("expected idle"); return }
        #expect(reason == "Connect or set “shapes”.")
    }

    @Test func anEmptyListOfShapesIsRefused() async throws {
        var h = Harness()
        let none = h.add(SeriesNode.self, ["count": .integer(0)])
        let spheres = h.add(ImplicitSphereNode.self)
        let union = h.add(ImplicitUnionNode.self)
        h.wire(none, "values", to: spheres, "radius")
        h.wire(spheres, "implicit", to: union, "shapes")
        let report = try await h.run([union])
        #expect(report.error(union) == "Connect at least one shape to “shapes”.")
    }

    @Test func aFieldGradesTheBlendAndNegativeValuesAreWarnedAbout() async throws {
        var h = Harness()
        let gradient = h.add(LinearGradientNode.self, ["length": .number(10)])
        let union = h.add(ImplicitUnionNode.self)
        h.wire(spheres(&h), "implicit", to: union, "shapes")
        h.wire(gradient, "field", to: union, "blend radius")
        let report = try await h.run([union])
        let solid = try #require(report.implicitSolid(union))
        #expect(solid.description.contains("blend linear(length 10)"))
        #expect(solid.lipschitz > 1, "a graded blend raises the lipschitz bound")
        #expect(report.warning(union) == "“blend radius” is below 0 in places; it is held at 0 there.")
    }

    @Test func aDistanceToASolidGradesTheBlendThroughABake() async throws {
        var h = Harness()
        let kernel = FakeKernel()
        let box = h.box(10, 10, 10)
        let distance = h.add(DistanceFieldNode.self)
        let clamp = h.add(FieldClampNode.self, ["low": .number(0), "high": .number(3)])
        let union = h.add(ImplicitUnionNode.self)
        h.wire(box, "solid", to: distance, "target")
        h.wire(distance, "field", to: clamp, "field")
        h.wire(clamp, "field", to: union, "blend radius")
        h.wire(spheres(&h), "implicit", to: union, "shapes")
        let report = try await h.run([union], kernel: kernel)
        let solid = try #require(report.implicitSolid(union), "\(String(describing: report.state(union)))")
        guard case .union(_, let blend) = solid else { Issue.record("not a union"); return }
        #expect(blend.baked.count == 1 && blend.range == 0...3)
        #expect(report.isOK(union))
    }
}

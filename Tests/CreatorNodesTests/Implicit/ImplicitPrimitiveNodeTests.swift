import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import Testing
@testable import CreatorNodes

/// Sphere, Box and Cylinder (implicit spec §3.2).
struct ImplicitPrimitiveNodeTests {
    @Test func theDefaultSphereIsTenMillimetresOfRadius() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self)
        let report = try await h.run([sphere])
        let solid = try #require(report.implicitSolid(sphere))
        #expect(solid.description == "sphere(radius 10 mm)")
        #expect(solid.distance(10, 0, 0) == 0 && solid.distance(0, 0, 0) == -10)
        #expect(solid.lipschitz == 1)
    }

    @Test func aSphereRefusesAnEmptyRadius() async throws {
        var h = Harness()
        let zero = h.add(ImplicitSphereNode.self, ["radius": .number(0)])
        let infinite = h.add(ImplicitSphereNode.self, ["radius": .number(.infinity)])
        let report = try await h.run([zero, infinite])
        #expect(report.error(zero) == "“radius” must be greater than 0 mm.")
        #expect(report.error(infinite) == "“radius” must be greater than 0 mm.")
    }

    @Test func aBoxIsCentredAndRoundedOnRequest() async throws {
        var h = Harness()
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(20, 10, 4)), "corner radius": .number(1)])
        let report = try await h.run([box])
        let solid = try #require(report.implicitSolid(box))
        #expect(solid.description == "box(20 × 10 × 4 mm, corner radius 1 mm)")
        #expect(solid.distance(10, 0, 0) == 0 && solid.distance(0, 5, 0) == 0 && solid.distance(0, 0, 2) == 0)
        #expect(solid.bounds == BoundingBox(min: Vector3(-10, -5, -2), max: Vector3(10, 5, 2)))
    }

    @Test func theDefaultBoxIsASharpTwentyMillimetreCube() async throws {
        var h = Harness()
        let box = h.add(ImplicitBoxNode.self)
        let solid = try #require(try await h.run([box]).implicitSolid(box))
        #expect(solid.description == "box(20 × 20 × 20 mm)")
    }

    @Test func aBoxRefusesAnEmptySideOrACornerThatDoesNotFit() async throws {
        var h = Harness()
        let flat = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(10, 0, 10))])
        let round = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(10, 10, 4)), "corner radius": .number(2.5)])
        let negative = h.add(ImplicitBoxNode.self, ["corner radius": .number(-1)])
        let report = try await h.run([flat, round, negative])
        #expect(report.error(flat) == "“size” must be greater than 0 mm on every side.")
        #expect(report.error(round) == "“corner radius” can't be more than half the smallest side.")
        #expect(report.error(negative) == "“corner radius” must be 0 or more.")
    }

    @Test func aCylinderStandsOnItsAxisAlongZ() async throws {
        var h = Harness()
        let cylinder = h.add(ImplicitCylinderNode.self, ["radius": .number(3), "height": .number(8)])
        let solid = try #require(try await h.run([cylinder]).implicitSolid(cylinder))
        #expect(solid.description == "cylinder(radius 3 mm, height 8 mm)")
        #expect(solid.distance(3, 0, 0) == 0 && solid.distance(0, 0, 4) == 0 && solid.distance(0, 0, 0) == -3)
    }

    @Test func aCylinderRefusesAnEmptyRadiusOrHeight() async throws {
        var h = Harness()
        let thin = h.add(ImplicitCylinderNode.self, ["radius": .number(0)])
        let flat = h.add(ImplicitCylinderNode.self, ["height": .number(-1)])
        let report = try await h.run([thin, flat])
        #expect(report.error(thin) == "“radius” must be greater than 0 mm.")
        #expect(report.error(flat) == "“height” must be greater than 0 mm.")
    }

    @Test func aListOfRadiiMakesAListOfSpheres() async throws {
        var h = Harness()
        let radii = h.add(SeriesNode.self, ["start": .number(2), "step": .number(3), "count": .integer(3)])
        let spheres = h.add(ImplicitSphereNode.self)
        h.wire(radii, "values", to: spheres, "radius")
        let solids = try #require(try await h.run([spheres]).value(spheres, "implicit")?.implicitSolids)
        #expect(solids.map(\.description) == ["sphere(radius 2 mm)", "sphere(radius 5 mm)", "sphere(radius 8 mm)"])
    }

    @Test func theNodesLiveInTheImplicitCategory() {
        for node: any NodeDefinition.Type in [ImplicitSphereNode.self, ImplicitBoxNode.self, ImplicitCylinderNode.self] {
            #expect(node.category == .implicit && node.outputs.map(\.type) == [.implicit])
        }
        let names = [ImplicitSphereNode.displayName, ImplicitBoxNode.displayName, ImplicitCylinderNode.displayName]
        #expect(names == ["Sphere", "Box", "Cylinder"])
    }
}

import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Drain Holes (implicit spec §3.6): after the node, the void count is 0.
struct DrainHolesNodeTests {
    /// A ball of radius 3 with a sealed cavity of radius 1.5, as an implicit solid.
    func ball(_ h: inout Harness) -> Node {
        let radii = h.add(SeriesNode.self, ["start": .number(3), "step": .number(-1.5), "count": .integer(2)])
        let spheres = h.add(ImplicitSphereNode.self)
        let subtract = h.add(ImplicitSubtractNode.self)
        h.wire(radii, "values", to: spheres, "radius")
        h.wire(spheres, "implicit", to: subtract, "shapes")
        return subtract
    }

    /// The part through Drain Holes (or not), meshed and checked for voids.
    func voids(after drain: Node?, ball: Node, _ h: inout Harness) -> Node {
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.2)])
        let check = h.add(CheckTrappedVolumesNode.self)
        h.wire(drain ?? ball, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: check, "mesh")
        return check
    }

    @Test func automaticDrillingLeavesNoEnclosedVoid() async throws {
        var h = Harness()
        let part = ball(&h)
        let before = voids(after: nil, ball: part, &h)
        let drain = h.add(DrainHolesNode.self, ["diameter": .number(0.8)])
        h.wire(part, "implicit", to: drain, "implicit")
        let after = voids(after: drain, ball: part, &h)
        let report = try await h.runForExport([before, after])
        #expect(report.warning(before) == "1 enclosed void can't drain.")
        #expect(report.isOK(after), "\(String(describing: report.state(after)))")
        let drilled = try #require(report.triangleMesh(after))
        let topology = MeshTopology(drilled)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2, "one shell: a ball with a dent")
        #expect(drilled.signedVolume < (try #require(report.triangleMesh(before))).signedVolume)
        #expect(report.isOK(drain))
    }

    @Test func atPointsDrillsFromEachPointAlongTheDirection() async throws {
        var h = Harness()
        let part = ball(&h)
        let point = h.add(VectorNode.self, ["x": .number(0), "y": .number(0), "z": .number(-1.2)])
        let drain = h.add(DrainHolesNode.self, ["mode": .integer(0), "diameter": .number(0.8)])
        h.wire(part, "implicit", to: drain, "implicit")
        h.wire(point, "vector", to: drain, "points")
        let report = try await h.run([drain])
        let drilled = try #require(report.implicitSolid(drain))
        #expect(drilled.distance(0, 0, -2.5) > 0 && drilled.distance(0, 0, 2.5) < 0)
    }

    @Test func aHoleTooSmallForTheCheckToSeeWarnsAndTheDefaultDoesNot() async throws {
        var h = Harness()
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let thin = h.add(DrainHolesNode.self, ["diameter": .number(1)])
        let usual = h.add(DrainHolesNode.self)
        h.wire(box, "implicit", to: thin, "implicit")
        h.wire(box, "implicit", to: usual, "implicit")
        let report = try await h.run([thin, usual])
        #expect(report.warning(thin) == "A hole of 1 mm is smaller than Check Trapped Volumes can see through (2 mm for this part), "
            + "so it may still report the void.")
        #expect(report.warning(usual) == nil)
        #expect(CheckWording.smallHole(diameter: 2, seen: 2).isEmpty)
    }

    @Test func aSolidWithNoVoidIsPassedThroughAsItIs() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(3)])
        let drain = h.add(DrainHolesNode.self)
        h.wire(sphere, "implicit", to: drain, "implicit")
        let report = try await h.run([sphere, drain])
        #expect(report.implicitSolid(drain) == report.implicitSolid(sphere) && report.isOK(drain))
    }

    @Test func badSettingsAreRefusedInPlainWords() async throws {
        var h = Harness()
        let part = ball(&h)
        let noPoints = h.add(DrainHolesNode.self, ["mode": .integer(0)])
        let noDirection = h.add(DrainHolesNode.self, ["direction": .vector(.zero)])
        let thin = h.add(DrainHolesNode.self, ["diameter": .number(0.01)])
        for node in [noPoints, noDirection, thin] { h.wire(part, "implicit", to: node, "implicit") }
        let report = try await h.run([noPoints, noDirection, thin])
        #expect(report.error(noPoints) == "Connect points to “points”, or choose Automatic.")
        #expect(report.error(noDirection) == "“direction” can't be zero.")
        #expect(report.error(thin) == "“diameter” must be at least 0.1 mm.")
    }
}

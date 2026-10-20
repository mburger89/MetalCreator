import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Decimate (implicit spec §3.6, §4.5).
struct DecimateNodeTests {
    /// A box with rounded edges, meshed by the Mesh node at 0.5 mm: lots of flat triangles on its faces.
    func decimated(_ h: inout Harness, tolerance: Double = 0.05) -> (mesh: Node, decimate: Node) {
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(12, 8, 6))])
        let mesh = h.add(MeshNode.self, ["preview resolution": .number(0.5)])
        let decimate = h.add(DecimateNode.self, ["tolerance": .number(tolerance)])
        h.wire(box, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: decimate, "mesh")
        return (mesh, decimate)
    }

    @Test func aBoxLosesItsFlatTrianglesAndStaysAClosedManifold() async throws {
        var h = Harness()
        let (mesh, decimate) = decimated(&h)
        let report = try await h.run([decimate])
        let before = try #require(report.triangleMesh(mesh)), after = try #require(report.triangleMesh(decimate))
        #expect(after.triangleCount < before.triangleCount / 4, "\(before.triangleCount) → \(after.triangleCount)")
        let topology = MeshTopology(after)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        #expect(abs(after.signedVolume - before.signedVolume) / before.signedVolume < 0.01)
        #expect(after.id != before.id && after.source == nil && after.resolution == before.resolution && after.quality == before.quality)
        #expect(report.isOK(decimate))
    }

    @Test func theInspectorShowsTrianglesBeforeAndAfter() async throws {
        var h = Harness()
        let (mesh, decimate) = decimated(&h)
        let report = try await h.run([decimate])
        let before = try #require(report.triangleMesh(mesh)), after = try #require(report.triangleMesh(decimate))
        let fact = try #require(after.inspectorFacts.first { $0.label == "Decimated" })
        let was = before.triangleCount.formatted(.number.locale(.messages)), now = after.triangleCount.formatted(.number.locale(.messages))
        #expect(fact.value == "\(was) → \(now) triangles")
        #expect(after.inspectorFacts.last?.label == "Memory")
    }

    @Test func anImplicitWiredStraightInIsMeshedAtTheDefaultsFirst() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(6)])
        let decimate = h.add(DecimateNode.self)
        h.wire(sphere, "implicit", to: decimate, "mesh")
        let report = try await h.run([decimate])
        let made = try #require(report.triangleMesh(decimate))
        #expect(MeshTopology(made).isClosedManifold && made.triangleCount > 100)
    }

    @Test func aToleranceThatIsTooSmallOrNotANumberIsRefused() async throws {
        var h = Harness()
        let (_, small) = decimated(&h, tolerance: 0.00001)
        let (_, nan) = decimated(&h, tolerance: .nan)
        let report = try await h.run([small, nan])
        #expect(report.error(small) == "“tolerance” must be at least 0.0001 mm.")
        #expect(report.error(nan) != nil)
    }

    @Test func aBiggerToleranceKeepsFewerTriangles() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(6)])
        let mesh = h.add(MeshNode.self, ["preview resolution": .number(0.4)])
        let tight = h.add(DecimateNode.self, ["tolerance": .number(0.002)])
        let loose = h.add(DecimateNode.self, ["tolerance": .number(0.05)])
        h.wire(sphere, "implicit", to: mesh, "implicit")
        for node in [tight, loose] { h.wire(mesh, "mesh", to: node, "mesh") }
        let report = try await h.run([tight, loose])
        let (a, b) = (try #require(report.triangleMesh(tight)), try #require(report.triangleMesh(loose)))
        #expect(b.triangleCount < a.triangleCount && MeshTopology(b).isClosedManifold)
    }
}

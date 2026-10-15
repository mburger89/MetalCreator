import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation
import Testing
@testable import CreatorNodes
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

/// Mesh to Solid (implicit spec §3.6): the cap in the spec's words, and, on OpenCascade, the solid.
struct MeshToSolidNodeTests {
    func solidOfASphere(_ h: inout Harness) -> (mesh: Node, solid: Node) {
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(3)])
        let mesh = h.add(MeshNode.self, ["preview resolution": .number(0.4)])
        let solid = h.add(MeshToSolidNode.self)
        h.wire(sphere, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: solid, "mesh")
        return (mesh, solid)
    }

    @Test func aMeshAboveTheLimitIsRefusedInTheSpecsWords() {
        #expect(throws: Never.self) { try MeshToSolidNode.requireWithinLimit(100_000) }
        #expect(throws: NodeError.invalidValue("Mesh has 100,001 triangles; Mesh to Solid takes at most 100,000. "
            + "Decimate it first or coarsen the resolution.")) { try MeshToSolidNode.requireWithinLimit(100_001) }
        #expect(throws: NodeError.invalidValue("Mesh has 2,000,000 triangles; Mesh to Solid takes at most 100,000. "
            + "Decimate it first or coarsen the resolution.")) { try MeshToSolidNode.requireWithinLimit(2_000_000) }
    }

    @Test func aKernelWithNoBrepSaysSo() async throws {
        var h = Harness()
        let solid = solidOfASphere(&h).solid
        let fake = try await h.run([solid])
        #expect(fake.error(solid) == "Mesh to solid isn't supported by this kernel yet.")
        let none = try await h.run([solid], kernel: KernelUnavailable())
        #expect(none.error(solid) == "Geometry isn't available on this platform yet.")
    }

    #if canImport(CreatorOCCT)
    @Test func aMeshedBallBecomesAFacetedSolidOfTheSameVolumeThatExportsAsStep() async throws {
        var h = Harness()
        let (meshNode, solidNode) = solidOfASphere(&h)
        let output = h.add(OutputNode.self)
        h.wire(solidNode, "solid", to: output, "solid")
        let kernel = OCCTKernel()
        let report = try await h.run([output], kernel: kernel)
        #expect(report.isOK(solidNode), "\(String(describing: report.state(solidNode)))")
        let made = try onlySolid(report, solidNode)
        let mesh = try #require(report.triangleMesh(meshNode))
        #expect(made.topology.faces.count > 1_000 && made.topology.faces.count <= mesh.triangleCount, "facets in one plane are merged")
        let found = try await volume(made, kernel)
        #expect(abs(found - mesh.signedVolume) / mesh.signedVolume < 1e-6, "\(found) against \(mesh.signedVolume)")
        let url = URL.temporaryDirectory.appending(path: "mesh-to-solid-node-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([made], format: .step, to: url)
        #expect(((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) > 1_000)
    }

    /// A decimated mesh's neighbouring planes differ by float noise, so the shim (vertices and edges shared by index, only exactly
    /// coplanar neighbours unified, no `BRepBuilderAPI_Sewing`) merges fewer faces than it does for an exact mesh. Fewer merged faces is
    /// expected; an invalid solid or a lost volume is not.
    @Test(arguments: ["ball", "bracket"])
    func aDecimatedMeshBecomesAValidSolidOfTheMeshsVolumeWithFewerFacesThanTheMeshHadTriangles(_ part: String) async throws {
        var h = Harness()
        let shape: Node
        if part == "ball" {
            shape = h.add(ImplicitSphereNode.self, ["radius": .number(5)])
        } else {
            let plate = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(20, 14, 5))])
            let hole = h.add(ImplicitCylinderNode.self, ["radius": .number(2), "height": .number(8)])
            shape = h.add(ImplicitSubtractNode.self)
            h.wire(plate, "implicit", to: shape, "shapes")
            h.wire(hole, "implicit", to: shape, "shapes")
        }
        let mesh = h.add(MeshNode.self, ["preview resolution": .number(0.5)])
        let decimate = h.add(DecimateNode.self, ["tolerance": .number(0.05)])
        let solid = h.add(MeshToSolidNode.self)
        let output = h.add(OutputNode.self)
        h.wire(shape, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: decimate, "mesh")
        h.wire(decimate, "mesh", to: solid, "mesh")
        h.wire(solid, "solid", to: output, "solid")
        let kernel = OCCTKernel()
        let report = try await h.run([output], kernel: kernel)
        #expect(report.isOK(solid), "\(String(describing: report.state(solid)))")
        let before = try #require(report.triangleMesh(mesh)), after = try #require(report.triangleMesh(decimate))
        let made = try onlySolid(report, solid)
        let shapeOfSolid = try await kernel.shape(of: made)
        #expect(OCCTKernel.serialized { shapeOfSolid.isValid })
        let faces = made.topology.faces.count
        #expect(faces >= 4 && faces <= after.triangleCount && after.triangleCount < before.triangleCount / 2,
                "\(before.triangleCount) → \(after.triangleCount) triangles → \(faces) faces")
        if part == "ball" {
            #expect(faces == after.triangleCount, "no two facets of a curved surface are coplanar, so none merge")
        } else {
            #expect(faces < after.triangleCount && faces >= 6, "the flat sides merge into few faces, but not always into six")
        }
        let found = try await volume(made, kernel)
        #expect(abs(found - after.signedVolume) / after.signedVolume < 1e-6, "\(found) against \(after.signedVolume)")
    }
    #endif
}

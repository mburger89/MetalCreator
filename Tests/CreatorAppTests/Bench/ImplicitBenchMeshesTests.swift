import CreatorImplicit
import Testing
@testable import CreatorApp

/// The meshes of rows i-5 and i-6 have the sizes the rows name, and are closed surfaces facing outwards.
struct ImplicitBenchMeshesTests {
    @Test func theOctahedralSphereHasEightTimesFourToTheNTriangles() {
        for level in 0...4 {
            let sphere = ImplicitBenchMeshes.sphere(subdivisions: level, radius: 10)
            #expect(sphere.triangleCount == 8 * Int(pow4(level)))
        }
        let mesh = ImplicitBenchMeshes.sphere(subdivisions: 3, radius: 10)
        let checked = TriangleMesh(positions: mesh.positions, triangles: mesh.triangles)
        #expect(MeshTopology(checked).isClosedManifold && MeshTopology(checked).eulerCharacteristic == 2)
        let exact = 4.0 / 3 * Double.pi * 1_000
        #expect(abs(checked.signedVolume - exact) / exact < 0.05 && checked.signedVolume > 0)
    }

    @Test func theLatitudeAndLongitudeSphereHasTheTrianglesItWasAskedFor() {
        let sphere = ImplicitBenchMeshes.uvSphere(segments: 40, rings: 26, radius: 10)
        #expect(sphere.triangleCount == 2 * 40 * 25)
        let checked = TriangleMesh(positions: sphere.positions, triangles: sphere.triangles)
        #expect(MeshTopology(checked).isClosedManifold && MeshTopology(checked).eulerCharacteristic == 2 && checked.signedVolume > 0)
        #expect(ImplicitBenchMeshes.uvSphere(segments: 400, rings: 126).triangleCount == 100_000)
    }

    func pow4(_ level: Int) -> Int { (0..<level).reduce(1) { value, _ in value * 4 } }
}

import CreatorImplicit
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorNodes

/// What each reader makes of a fixed file, pinned by a SHA-256 over the mesh's positions (little-endian `Float` bits) and triangles.
/// The same digests must come out on macOS, Linux and Windows: a reader whose answer depended on the platform's floating point
/// parsing, hashing order or inflate would show here.
struct ImportedMeshDigestTests {
    static func digest(_ mesh: TriangleMesh) -> String {
        var bytes = Data()
        for p in mesh.positions {
            for value in [p.x, p.y, p.z] { withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) } }
        }
        for index in mesh.triangles { withUnsafeBytes(of: UInt32(index).littleEndian) { bytes.append(contentsOf: $0) } }
        return SHA256.hex(of: bytes)
    }

    static func binarySTL() -> Data {
        var data = Data(count: 80)
        func put(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put(_ value: Float) { put(value.bitPattern) }
        let faces = Array(ImportMeshNodeTests.tetra.reversed())
        put(UInt32(faces.count))
        for face in faces {
            for _ in 0..<3 { put(Float(0)) }
            for p in [face.0, face.1, face.2] { put(p.x); put(p.y); put(p.z) }
            data.append(contentsOf: [0, 0])
        }
        return data
    }

    @Test func aMeshDigestIsPinned() throws {
        let binary = try STLReader.read(Self.binarySTL(), isCancelled: { false })
        let ascii = try STLReader.read(ImportMeshNodeTests.stl(ImportMeshNodeTests.tetra), isCancelled: { false })
        let tetra = ImportMeshNodeTests.tetra
        let objects = [ImportMeshNodeTests.shifted, Array(tetra.dropFirst()) + [tetra[0]]]
        let threeMF = try ThreeMFReader.read(try ThreeMFFixtures.package(objects), isCancelled: { false })
        #expect(threeMF.count == 2)
        #expect(Self.digest(binary.mesh) == "9f44c0ceb507e09dc742d9c1dbe8ba7e696d4fbeb61bf1d2aa9aa56f9fa4b5e9")
        #expect(Self.digest(ascii.mesh) == "9c0ccaebb07f9c9f19a1b178a19c202ff4d15356ccf97a235eca5e8611eed67e")
        #expect(Self.digest(threeMF[0].mesh) == "501dabfa685ff366c435c6dd69d693355d42074c9067fad0c5789eb1a1ff200d")
        #expect(Self.digest(threeMF[1].mesh) == "9ce89034336a8335cf85d4426e504c191caeb5d10f8ca77a9e47f38ffb23463d")
    }

    /// The stored fixture above has integer coordinates and no transform; this one is deflated, has fractional coordinates and a
    /// rotating transform, so the digest also covers `Inflate`, the float parser and the placement's arithmetic. Pinned from macOS and
    /// Linux alike.
    @Test func aDeflatedMeshWithFractionsAndARotationDigestIsPinned() throws {
        let meshes = try ThreeMFReader.read(DeflatedThreeMF.package, isCancelled: { false })
        #expect(meshes.count == 1 && meshes[0].mesh.triangleCount == 4)
        #expect(Self.digest(meshes[0].mesh) == "d017f27196b36ce2766caa98986777795fbac052f553584e5045904611c1cc72")
    }
}
